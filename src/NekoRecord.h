/* NekoRecord */

#import <Cocoa/Cocoa.h>

/*! "Avevo detto venerdì, no?"

   Stage 2 of docs/personality-roadmap.md, and stage 0 is what promoted it from a
   good idea to the only remaining answer. Measured there, on this Mac: the
   shipped prompt **agreed with a false premise 8 times out of 20** on the engine
   that actually answers. And the cheap fix was measured and thrown away — one
   sentence telling the model not to go along with a false premise gave a perfect
   false-premise arm and then denied **15 of 20 true** premises, saying things
   like *"No, il Colosseo non è a Roma. È a Roma, ma non è qui."* It had not
   learned to check a premise; it had learned to disagree.

   So no prompt fixes this. A sentence can move a small model's willingness to
   agree; it cannot give it anything to check against. What can is a line
   somebody actually wrote, and this application has a month of them.

   **It quotes. It does not judge.** That is the whole design, and it is narrower
   than the roadmap sketched on purpose: asked *"avevo detto venerdì?"* it answers
   *"Il 27 agosto hai scritto: «la riunione è giovedì»"* and stops. It never says
   who is right. A person reading their own sentence needs no help with the
   conclusion, and every mechanism that would supply one is a mechanism that can
   be wrong about it — which is the failure the roadmap named as the thing that
   would stop this stage.

   Four rules:

   - **Only from a written line.** Nothing is inferred, nothing is completed.
   - **Never a line the cat said itself.** `-recordAbout:limit:` refuses `sed`
     lines: quoting its own remark back as the record is the loop
     `tools/diary.py` found, wearing a tie.
   - **Nothing written down is an answer**, and it is said rather than guessed
     around. This is the one place the application would otherwise fall through
     to a model holding a false premise.
   - **Not while a conversation is live.** Asked inside three minutes of an
     earlier turn, the question is about what was just said and the thread has
     it; the record is for the questions that reach back further. That check is
     in `NekoAsk`, where the turns are. */
@interface NekoRecord : NSObject

/*! Whether the sentence is asking what somebody said or wrote before — or
   **when** they did, which is the same diary read for a different answer.

   The two are worth telling apart. Asked *what* it quotes the line and puts the
   day in front of it; asked *when* it answers with the day and **how long ago**,
   and nothing else. The elapsed part is the addition: a date is a fact about the
   calendar, and "six days ago" is a fact about the two of you. docs/self.md §4
   is why that has to be a subtraction rather than something a model works out —
   on the largest temporal benchmark, relating two times drops the same model
   from strong to about half, and this application measured three of its own at
   one of nine with the date already in the prompt. */
+ (BOOL)wantedFor:(NSString *)question;

/*! Whether that question was a *when*. Exposed because the difference is the
   whole of this addition and a harness should be able to see it. */
+ (BOOL)asksWhen:(NSString *)question;

/*! The lines, quoted with the day they were written — or the sentence that says
   there are none. Never nil once ``-wantedFor:`` has said yes. */
+ (NSString *)answerFor:(NSString *)question;

@end
