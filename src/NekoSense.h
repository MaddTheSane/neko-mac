/* NekoSense */

#import <Cocoa/Cocoa.h>

/*! The last gate before the cat opens its mouth.

   Small models fail in ways that are obvious to a reader and easy to spot in
   code: the same word four times over, an answer in the wrong language, one of
   the example lines handed straight back, a paragraph where a sentence was
   asked for. None of that is worth showing, and a cat that says nothing is
   better than a cat that says "Codice, codice, codice, codice."

   It judges what the cat says on its own, where saying nothing is a perfectly
   good outcome. An answer to a question asked out loud does not come through
   here: dropping that would leave somebody who asked something staring at a
   cat, which is worse than a clumsy sentence.

   Everything here is a rejection, never a repair: a line is shown as written or
   not at all. */
@interface NekoSense : NSObject

/*! `NO` when the line should be thrown away. */
+ (BOOL)isWorthSaying:(NSString *)line;

/*! Why it was thrown away, for the preferences and the logs. nil when it passes. */
+ (NSString *)problemWith:(NSString *)line;

/*! The same, judged also against **what the cat could actually see** when it said
   it — the desktop summary and the lines of diary that went into the prompt.

   One check needs that and cannot be made without it, and it is here because of
   a measurement rather than a hunch — and it is **narrower than it started**,
   because its own negative table said so: see -explainsSomethingItDidNotSee: for
   what it stopped trying to catch and why. `tools/diary.py`, run on eight days of real
   diary, found 65 remarks carrying 11 distinct thoughts, and the content was:

   ```
       L'orario attuale 10:44, mercoledì 26 agosto 2026, Xcode aperto recente
       build lento perché progetto grande
   ```

   The first reads the clock back — which the suggestion prompt **already
   forbids**, in so many words, and which happened 22 times anyway. The second
   names nothing that was on the screen: there is no "build" and no "progetto" in
   anything the cat was shown. `tests/persona.m` produced two more of that family
   the same afternoon, unprompted: *"il build è lento perché i server sono
   sovraccarichi"* — there are no servers.

   Both are in Völkel et al.'s tenth factor for conversational agents, the one
   they named *Artificial*, whose top twenty descriptors include **vague**,
   **superficial** and **monotonous** — an instrument built from 349 adjectives
   rated by 744 people rather than from our own judgement. See
   docs/personality.md §3.

   Passing nil for `seen` is exactly the old behaviour. */
+ (NSString *)problemWith:(NSString *)line seeing:(NSString *)seen;
+ (BOOL)isWorthSaying:(NSString *)line seeing:(NSString *)seen;

/* The first word in the line that the system dictionary does not know, or nil.
   Names, versions and file names are left alone. */
+ (NSString *)unknownWordIn:(NSString *)line;

/* Whether a line is not in the language the application is running in. Public
   because it is one of the few things about a character that a test can see:
   answering in the wrong language is the first thing to go when a prompt gets
   long. */
+ (BOOL)isInTheWrongLanguage:(NSString *)line;

@end
