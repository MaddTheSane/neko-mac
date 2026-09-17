/* NekoRecall */

#import <Cocoa/Cocoa.h>

/*! Finding the lines of a diary that bear on a question.

   The diary is a month of short lines and the prompt has room for about three of
   them, so the whole problem is which three. Until now the answer was "the newest
   three", which is right for a follow-up and wrong for everything else: something
   decided three weeks ago was written down and then never found again.

   **Why this is words and not a model.** The plan said to embed every line with
   `NLEmbedding`, which is on the machine and needs no permission. Measured on a
   staged Italian diary of twenty lines and ten questions, before any of it was
   built:

   | | top-1 | top-3 | a month costs | on disk |
   | --- | --- | --- | --- | --- |
   | NLEmbedding, cosine | 5/10 | 5/10 | 5.5 s | 3.7 MB |
   | bare shared words | 8/10 | — | — | — |
   | lemmas + word class + rarity | 8/10 | 8/10 | 267 ms | nothing |
   | the two fused by rank | 6/10 | 9/10 | 5.5 s | 3.7 MB |

   The embedding lost to counting words, and fusing the two bought **one question
   in ten** on top-3 — which is inside the noise of a ten-question sample — for
   twenty times the time and 3.7 MB of vectors sitting beside a file whose whole
   promise is that it is plain text somebody can read. So: no embedding. If recall
   turns out to be weak in use, that table is where to start arguing with this
   decision, and the fusion is four lines of code.

   Three things do the work, all of them from NLTagger, all of them in the four
   languages this application speaks:

   1. **Lemmas.** "Ascolto" and "ha ascoltato" are the same word asked twice.
   2. **Word class.** A question is about its nouns; the verbs it is asked with —
      usare, fare, avere — are how a language carries a question. Nouns count 1.0,
      adjectives 0.8, verbs and adverbs 0.35, and the rest not at all.
   3. **Rarity.** A word that is in every line of the diary says nothing about
      which line. Plain inverse document frequency, the cheap half of BM25.

   And one rule decides whether a line is about the question at all: **it has to
   share a word of substance** — a noun, a name, a number, an adjective. Measured:
   of eight questions about things not in the diary, six came back with a line, and
   five of those six shared exactly one word, which was `fare`, `essere` or `come`.
   A verb is how a question is carried, not what it is about.

   What it cannot do is synonyms: asked about *"impostazioni"* it does not find
   *"preferenze"*. That is measured, it is in `tests/recall.m` as a known miss
   rather than hidden, and it is the one thing a sentence embedding was better at —
   fifth of twenty, which would still not have reached a prompt with room for
   three.

   **The obvious fix was tried and does not work**, and it is written down here so
   that the next person tries something else. `NLEmbedding` also has *word*
   vectors, with a neighbours call, which is the natural way to widen a question:
   take each word somebody asked about and add what is nearest to it. Measured on
   this Mac, Italian, 49,620 words:

   | pair | distance | wanted |
   | --- | --- | --- |
   | gatto ↔ cane | **0.660** | out — a different animal |
   | gatto ↔ coniglio | 0.659 | out |
   | caffè ↔ tè | 0.865 | out |
   | riunione ↔ assemblea | 0.859 | in |
   | problema ↔ difetto | 0.898 | in |
   | **versione ↔ release** | **0.922** | **in — the same thing, two words** |
   | riunione ↔ votazione | 0.971 | out |
   | treno ↔ aereo | 1.106 | out |
   | impostazioni ↔ preferenze | 1.157 | in |

   There is no threshold. The pairs that should widen a search span 0.70 to 1.16
   and the pairs that must not span 0.66 to 1.11, and two different animals sit
   closer together than two words for the same thing. That is not a flaw in the
   vectors: distributional similarity means "turns up in the same sort of
   sentence", which is exactly why a cat and a dog are neighbours, and it is not
   what synonymy means. Apple's Italian vectors also read *preferenze* in its
   voting sense — its neighbours are *voto, votante, consenso* — so the pair that
   started all this would have missed anyway.

   The system dictionary was tried next and is a dead end for a different reason.
   `DCSCopyTextDefinition` **is** reachable from inside the sandbox, which is
   worth knowing on its own — but it answers with a definition, not a list of
   synonyms, and an Italian dictionary opens *impostazione* on its architectural
   sense and never mentions *preferenze* at all. Parsing lexicographic prose to
   find a synonym is a larger and worse idea than the problem.

   **What was tried next, and works: `NekoWords`.** The diary's own vocabulary is
   put in front of the on-device model and it is asked which of *those* words mean
   the same as the one somebody asked with — recognition rather than generation,
   which is the only one of the three shapes that answered *impostazioni* with
   *preferenze*. That header has the table. This one takes the result as data:
   a dictionary of word to words, passed in, so that recall stays a pure function
   of a question and a corpus and a test can stage a table that was never learned.

   A word arrived at that way is worth **0.7** of the word actually asked, so a
   line that shares the real word always beats a line that shares its synonym. */
@interface NekoRecall : NSObject

/*! The words of a line, lemmatised and folded, with the short ones dropped. */
+ (NSArray *)wordsOf:(NSString *)text;

/*! The words of a question, each with what its word class is worth. */
+ (NSDictionary<NSString*,NSNumber*> *)askedIn:(NSString *)question;

/*! The same, with what somebody's diary calls those words added at a discount.
   `synonyms` maps a word to the words that mean it; nil is the plain version. */
+ (NSDictionary *)askedIn:(NSString *)question widenedBy:(NSDictionary *)synonyms;

/*! How rare each word is across a body of lines. Pass it back to -linesIn:… so a
   month is only measured once. */
+ (NSDictionary *)rarityAcross:(NSArray *)lines;

/*! The words of every line, in order, as sets. Lemmatising a month costs a quarter
   of a second; doing it again on every question would cost a quarter of a second
   somebody waits for nothing, so it is done once and handed back in. */
+ (NSArray *)wordSetsFor:(NSArray *)lines;

/*! The lines that bear on the question, best first, and never more than `limit`.
   Empty when nothing bears on it: a question about the weather may not drag
   somebody's month into the prompt behind it. */
+ (NSArray *)linesIn:(NSArray *)lines
               about:(NSString *)question
               limit:(NSUInteger)limit
              rarity:(NSDictionary *)rarity;

/*! The same, with the lines' words already worked out. */
+ (NSArray *)linesIn:(NSArray *)lines
               words:(NSArray *)sets
               about:(NSString *)question
               limit:(NSUInteger)limit
              rarity:(NSDictionary *)rarity;

/*! And the same again, widened by what this Mac has learned the words mean. */
+ (NSArray *)linesIn:(NSArray *)lines
               words:(NSArray *)sets
               about:(NSString *)question
               limit:(NSUInteger)limit
              rarity:(NSDictionary *)rarity
            synonyms:(NSDictionary *)synonyms;

/*! The score a line has to reach to count as being about the question at all.
   Exposed because there is now a second caller scoring lines itself, and two
   different bars would be two different ideas of what "about" means. */
+ (double)floor;

/*! What a line scored, exposed so a test can say why rather than only whether. */
+ (double)scoreOf:(NSString *)line asked:(NSDictionary *)asked
           rarity:(NSDictionary *)rarity;
+ (double)scoreOfWords:(NSSet *)words asked:(NSDictionary *)asked
                rarity:(NSDictionary *)rarity;

@end
