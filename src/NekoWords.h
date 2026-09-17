/* NekoWords */

#import <Cocoa/Cocoa.h>

/* The words this Mac has learned mean the same thing.

   `NekoRecall` finds the diary's lines by lemma, word class and rarity, and its
   header says at length what it cannot do: asked about *impostazioni* it does not
   find *preferenze*. Two ways out were measured there and both are dead ends —
   `NLEmbedding`'s word vectors have no threshold that separates *versione ↔
   release* (0.922, wanted) from *gatto ↔ cane* (0.660, not wanted), and the
   system dictionary answers with definitions.

   This is the third way, and it was measured before it was built. Three things
   were asked of the on-device model, and only one of them works:

   | asked | result |
   | --- | --- |
   | **generate** — "synonyms for *impostazioni*" | *configurazione, parametri, opzioni, regolazioni* — good words, and **not the one in the diary**. For *versione*: *variante, edizione, iterazione*, never *release* |
   | **precompute in reverse** — "what would somebody ask *preferenze* with" | *cosa preferisci, quali gusti…* — phrases, not the single word wanted |
   | **recognise** — "here are the words this diary uses; which of them mean the same as *impostazioni*" | **preferenze.** And *versione → release*, *incontro → riunione* |

   So the working shape is recognition, not generation, and recognition needs the
   question — which is why none of this can be worked out in advance.

   That leaves a problem of when. Recall is synchronous, called while the prompt
   is being built, and a model call is neither. Asking for an expansion there
   would put six tenths of a second in front of **every** question the diary has
   nothing for, which is most of them.

   So it learns afterwards. A question the diary answered nothing for leaves the
   word behind; when the cat is next not busy, one word is asked about, once, and
   the answer is written to `synonyms.txt` beside the diary. The next question
   with that word in it is instant. The first one misses, and that is said out
   loud here rather than hidden: **this makes the second asking work, not the
   first.**

   **Measured once it was built**, on a staged diary of ten lines, against the
   twenty-three words of substance in it — `tests/words.m`, and the engine that
   answered was Apple Intelligence, which is what `bestOnDeviceProvider` picks on
   this Mac:

   | asked | offered back |
   | --- | --- |
   | impostazione | **preferenza**, applicazione |
   | versione | **release** |
   | programma | **applicazione**, plugin |
   | errore | **crash** |
   | estensione | **plugin** |
   | felino | **gatto**, tigre |
   | bicicletta · oceano · pianoforte | *nothing* |

   **Nine of nine**, in under a second each, with three words of slack — and the
   three that mean nothing here came back empty, which is the half that matters.
   The same prompt in Italian was measured beside it and did no better, so this
   asks in English like everything else does.

   Two things that made the difference, both of them found by measuring rather
   than by thinking: the candidates are **lemmas of substance only** — with the
   verbs still in the list the same question came back *aprire, cambiare,
   sistemare* — and the diary's own three-letter markers are gone with them.

   Four rules hold:

   - **Recognition only.** The model is given the diary's own vocabulary and its
     answer is intersected with it. A word it invents cannot survive, because a
     word that is not in the list is discarded by construction.
   - **The diary never leaves the Mac.** The vocabulary is diary content, so the
     engine is `NekoBrains bestOnDeviceProvider`, which is never a remote one.
   - **A word is asked about once.** A word nothing was found for is written down
     with nothing after it, so it is not asked again every day.
   - **Plain text, beside the diary, deletable.** Same promise as the diary
     itself: you can open it, read it, and delete a line you disagree with. */
@interface NekoWords : NSObject
{
	NSMutableDictionary *table;      /* word -> the diary's words for it */
	NSMutableArray *waiting;         /* questions the diary had nothing for */
	NSTimer *later;
	BOOL asking;
}

+ (NekoWords *)sharedWords;

/* Where the file is. Beside the diary, on purpose. */
- (NSURL *)file;

/* What is known, for NekoRecall to widen a question with. */
- (NSDictionary *)table;

/* A question the diary had nothing for. Takes the word worth asking about, if
   there is one, and asks about it later. */
- (void)missedOn:(NSString *)question;

/* For the harness: ask now and wait, rather than when the cat is idle. */
- (BOOL)learnNowFor:(NSString *)word among:(NSArray *)vocabulary;

/* What survives of an answer: only words that were in the list offered. Exposed
   because this is the guard the whole design rests on, and a guard nothing can
   fail loudly is not a guard. */
- (NSArray *)wordsOf:(NSString *)answer among:(NSArray<NSString*> *)candidates;

/* The word in a question worth asking about, or nil. Exposed for the same
   reason: "which word" is where this decides to spend a model call. */
- (NSString *)wordWorthAsking:(NSString *)question among:(NSArray<NSString*> *)vocabulary;

- (void)forgetEverything;

@end
