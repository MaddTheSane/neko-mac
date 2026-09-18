//  NekoLlamaEngine.mm
//
//  Runs a GGUF model on this Mac, through llama.cpp linked straight into the
//  app. No daemon, no package manager, no second application: the model file
//  the preferences downloaded, and this.
//
//  Objective-C++ because llama.cpp is a C library with C++ headers; everything
//  the rest of the app sees is the NekoLocalEngine protocol.

#import "NekoLocalProvider.h"
#import "llama.h"

#include <atomic>
#include <string>
#include <vector>

/*! Two short sentences, so there is no reason to let it run on. */
static const int NekoLlamaMaxTokens = 200;

/*! Raised for one answer when the provider says the chosen model writes its notes
   first — see `-setTokenBudget:` in NekoLocalProvider.h for the measurement. Zero
   means the ordinary budget. */
static int NekoLlamaBudget = 0;
static const int NekoLlamaContext = 4096;

/*! How many tokens go into one llama_decode. The prompt is fed in pieces of this
   size: handed the whole thing at once, llama.cpp does not return an error when
   it is larger than the batch — it calls abort(), and the app goes with it. That
   is exactly what happened when the instructions grew to carry the time, the
   date and the list of things the cat may do. */
static const int NekoLlamaBatch = 512;

@interface NekoLlamaEngine : NSObject <NekoLocalEngine>
@end

@implementation NekoLlamaEngine
{
	llama_model *model;
	llama_context *context;
	dispatch_queue_t queue;
	std::atomic<bool> stop;
}

+ (void)initialize
{
	if(self == [NekoLlamaEngine class])
		llama_backend_init();
}

- (id)init
{
	if((self = [super init]) != nil) {
		/* Serial: one question at a time, and never on the main thread. */
		queue = dispatch_queue_create("neko.llama", DISPATCH_QUEUE_SERIAL);
		stop = false;
		/* ggml checks at process exit that its Metal resources were released,
		   and aborts when they were not. Nothing deallocates a long-lived
		   engine before the app quits, so the model is freed here instead — a
		   crash on Quit is a poor way to end a conversation. */
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(applicationWillTerminate:)
			       name:NSApplicationWillTerminateNotification
			     object:nil];
	}
	return self;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[self teardown];
}

- (void)teardown
{
	[self cancel];
	dispatch_sync(queue, ^{});      /* let a running generation finish */
	if(context != NULL) {
		llama_free(context);
		context = NULL;
	}
	if(model != NULL) {
		llama_model_free(model);
		model = NULL;
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self teardown];
	queue = nil;
}

#pragma mark Loading

- (BOOL)isLoaded
{
	return model != NULL && context != NULL;
}

- (BOOL)loadModelAtURL:(NSURL *)file error:(NSError **)error
{
	if([self isLoaded])
		return YES;

	llama_model_params modelParams = llama_model_default_params();
	/* Everything on the GPU: Metal is compiled in, and a 0.5B model fits
	   comfortably on any Mac that can run this app. */
	modelParams.n_gpu_layers = 999;

	model = llama_model_load_from_file([[file path] fileSystemRepresentation], modelParams);
	if(model == NULL) {
		if(error != NULL)
			*error = [NSError errorWithDomain:NekoAskErrorDomain
			                             code:NekoAskErrorTransport
			                         userInfo:[NSDictionary dictionaryWithObject:
				NSLocalizedString(@"That model file could not be read", nil)
				                                                        forKey:NSLocalizedDescriptionKey]];
		return NO;
	}

	llama_context_params contextParams = llama_context_default_params();
	contextParams.n_ctx = NekoLlamaContext;
	contextParams.n_batch = NekoLlamaBatch;
	context = llama_init_from_model(model, contextParams);
	if(context == NULL) {
		llama_model_free(model);
		model = NULL;
		if(error != NULL)
			*error = [NSError errorWithDomain:NekoAskErrorDomain
			                             code:NekoAskErrorTransport
			                         userInfo:nil];
		return NO;
	}
	return YES;
}

#pragma mark Generating

/*! The model's own chat template when it has one, so Qwen is spoken to the way
   Qwen expects; a plain ChatML string otherwise, which is what these models use
   anyway. */
- (std::string)promptFor:(NSString *)question instructions:(NSString *)instructions
{
	std::string system = [instructions UTF8String] ?: "";
	std::string user = [question UTF8String] ?: "";

	const char *tmpl = llama_model_chat_template(model, NULL);
	if(tmpl != NULL) {
		llama_chat_message messages[2];
		messages[0].role = "system";
		messages[0].content = system.c_str();
		messages[1].role = "user";
		messages[1].content = user.c_str();

		std::vector<char> buffer((system.size() + user.size()) * 2 + 512);
		int32_t written = llama_chat_apply_template(tmpl, messages, 2, true,
		                                           buffer.data(), (int32_t)buffer.size());
		if(written > (int32_t)buffer.size()) {
			buffer.resize(written + 1);
			written = llama_chat_apply_template(tmpl, messages, 2, true,
			                                    buffer.data(), (int32_t)buffer.size());
		}
		if(written > 0)
			return std::string(buffer.data(), written);
	}

	return "<|im_start|>system\n" + system + "<|im_end|>\n<|im_start|>user\n"
	     + user + "<|im_end|>\n<|im_start|>assistant\n";
}

- (void)generateFor:(NSString *)question
       instructions:(NSString *)instructions
            partial:(void (^)(NSString *sofar))partial
         completion:(void (^)(NSString *answer, NSError *error))completion
{
	if(![self isLoaded]) {
		completion(nil, [NSError errorWithDomain:NekoAskErrorDomain
		                                    code:NekoAskErrorNotConfigured
		                                userInfo:nil]);
		return;
	}

	stop = false;
	/* Blocks are used in boolean context throughout: comparing one to nil is
	   rejected in Objective-C++, where nil is nullptr. */
	void (^partialCopy)(NSString *) = nil;
	if(partial)
		partialCopy = [partial copy];
	void (^completionCopy)(NSString *, NSError *) = [completion copy];
	std::string prompt = [self promptFor:question instructions:instructions];

	dispatch_async(queue, ^{
		const llama_vocab *vocab = llama_model_get_vocab(model);

		/* Tokenise: ask for the length first, then fill. */
		int32_t needed = -llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(),
		                                 NULL, 0, true, true);
		std::vector<llama_token> tokens(needed > 0 ? needed : 1);
		int32_t count = llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(),
		                               tokens.data(), (int32_t)tokens.size(), true, true);
		if(count <= 0) {
			[self finish:nil error:[NSError errorWithDomain:NekoAskErrorDomain
			                                          code:NekoAskErrorNoAnswer
			                                      userInfo:nil]
			     partial:partialCopy completion:completionCopy];
			return;
		}
		tokens.resize(count);

		llama_sampler *sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
		/* Without a penalty the small models fall into a groove and stay there:
		   asked for one line about Xcode, the 1.5B answered "Codice, codice,
		   codice, codice." Sixty-four tokens of history, a mild 1.15, is enough
		   to break the loop without making it write strangely. */
		llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
		llama_sampler_chain_add(sampler,
			llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.15f, 0.0f, 0.0f));
		llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9f, 1));
		llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7f));
		/* A fresh seed per generation. With the fixed default, the same prompt
		   produced the same sentence word for word — which is fine for a
		   question asked once and dismal for a cat that remarks on your work
		   every ten minutes in an application you have not left. */
		llama_sampler_chain_add(sampler, llama_sampler_init_dist(arc4random()));

		/* Each question starts from nothing. Without this the key-value cache
		   keeps every previous conversation, and after four questions of a few
		   hundred tokens the two thousand token context is full: llama_decode
		   fails, and the cat goes quiet until the app is restarted. */
		llama_memory_clear(llama_get_memory(context), true);

		std::string answer;
		int produced = 0;
		NSError *problem = nil;

		/* A prompt longer than the context cannot be answered at all, and is
		   refused here rather than left to the assert inside llama.cpp. */
		if((int)tokens.size() + NekoLlamaMaxTokens > NekoLlamaContext) {
			problem = [NSError errorWithDomain:NekoAskErrorDomain
			                              code:NekoAskErrorTransport
			                          userInfo:[NSDictionary dictionaryWithObject:
				NSLocalizedString(@"That was too much to think about at once.", nil)
				                                                          forKey:NSLocalizedDescriptionKey]];
		}

		/* The prompt goes in a batch at a time. */
		for(size_t offset = 0; problem == nil && offset < tokens.size();
		    offset += NekoLlamaBatch) {
			if(stop.load())
				break;
			int32_t piece = (int32_t)MIN((size_t)NekoLlamaBatch, tokens.size() - offset);
			llama_batch part = llama_batch_get_one(tokens.data() + offset, piece);
			if(llama_decode(context, part) != 0) {
				problem = [NSError errorWithDomain:NekoAskErrorDomain
				                              code:NekoAskErrorTransport
				                          userInfo:nil];
				break;
			}
		}

		const int allowed = NekoLlamaBudget > 0 ? NekoLlamaBudget : NekoLlamaMaxTokens;
		while(problem == nil && produced < allowed) {
			if(stop.load())
				break;

			llama_token next = llama_sampler_sample(sampler, context, -1);
			if(llama_vocab_is_eog(vocab, next))
				break;

			char piece[256];
			int32_t length = llama_token_to_piece(vocab, next, piece, sizeof(piece), 0, false);
			if(length > 0) {
				answer.append(piece, length);
				if(partialCopy) {
					NSString *sofar = [NSString stringWithUTF8String:answer.c_str()];
					if(sofar != nil)
						dispatch_async(dispatch_get_main_queue(), ^{ partialCopy(sofar); });
				}
			}

			produced++;
			/* The token just sampled is fed back in, so the next sampling sees
			   it. `next` outlives the call, which is all llama_decode needs. */
			llama_batch batch = llama_batch_get_one(&next, 1);
			if(llama_decode(context, batch) != 0) {
				problem = [NSError errorWithDomain:NekoAskErrorDomain
				                              code:NekoAskErrorTransport
				                          userInfo:nil];
				break;
			}
		}

		llama_sampler_free(sampler);

		NSString *whole = answer.empty() ? nil
			: [[NSString stringWithUTF8String:answer.c_str()]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if(whole == nil && problem == nil)
			problem = [NSError errorWithDomain:NekoAskErrorDomain
			                              code:NekoAskErrorNoAnswer
			                          userInfo:nil];
		[self finish:whole error:problem partial:partialCopy completion:completionCopy];
	});
}

- (void)finish:(NSString *)answer
         error:(NSError *)error
       partial:(void (^)(NSString *))partial
    completion:(void (^)(NSString *, NSError *))completion
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if(!stop.load())
			completion(answer, error);
		Block_release(completion);
		if(partial)
			Block_release(partial);
	});
}

- (void)setTokenBudget:(int)tokens
{
	NekoLlamaBudget = tokens;
}

- (void)cancel
{
	stop = true;
}

@end
