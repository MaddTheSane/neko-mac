/* NekoAppointment */

#import <Cocoa/Cocoa.h>

/*! "Metti in calendario la riunione con Marco venerdì alle 9:30."

   The route with no permission, which is the one docs/utilities.md ranked first
   and nobody built: the event is written as an `.ics` in this application's own
   container and handed to whatever opens those — Calendar, on every Mac measured.
   Calendar shows the whole event with its own Add button, so the last word is
   somebody looking at it in the application it belongs to. That is one click more
   than EventKit would be, and the click is in the right place.

   Measured before any of it was written, on this Mac:

   - a sandboxed application **can** write the file in its container and
     `CalendarFileHandler.app` is what would open it;
   - `NSDataDetector` parses the date out of an ordinary sentence in all four
     languages this application speaks — *domani alle 15*, *venerdì alle 9:30*,
     *tomorrow at 3pm*, *demain à 15h*, *el 3 de septiembre a mediodía* — and
     hands back the range of the words it used, which is how the rest of the
     sentence becomes the title;
   - and *"svegliami alle 7"*, said in the afternoon, comes back as **seven this
     morning**. That is the single likeliest way this feature says something
     wrong, and the rule for it is written down below rather than discovered
     later.

   What it will not do is decide on its own that a sentence was about an
   appointment. A date in a sentence is not a request — *"la riunione è durata due
   ore"* has one — so an explicit calendar phrase is required as well. The failure
   that matters here is not a missed appointment; it is one nobody asked for. */
@interface NekoAppointment : NSObject

/*! What the sentence asks to put in a calendar, or `nil`. The dictionary carries
   When, Ends, Title and Sentence — the last being what is read back. */
+ (NSDictionary *)wantedFor:(NSString *)question;

/*! Writes the file and hands it over. Answers with what to say. */
+ (NSString *)make:(NSDictionary *)appointment;

/*! The text of the file itself, so a test can read it without opening anything. */
+ (NSString *)calendarFileFor:(NSDictionary *)appointment;

@end
