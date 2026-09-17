#import "NekoUnseen.h"
#import "NekoFolderAccess.h"

#define NekoUnseenLocalized(key) NSLocalizedStringFromTable(key, @"Localizable", nil)

/* Each class of question, the phrases that ask it, and the one sentence that
   answers it. The phrases came from the questions stage 3 measured rather than
   from imagination, which is why there are seven groups and not twenty.

   Whole phrases, not single words: "conto" is in "tienine conto" and "il conto
   del ristorante", and neither is a question about somebody's bank. */
static NSArray<NSArray<NSString*>*> *NekoUnseenClasses(void)
{
	static NSArray<NSArray<NSString*>*> *const classes =
	@[
		/* Their own money. */
		@[@"accounts",
			@"I cannot see your accounts.",
			@"quanto ho sul conto", @"quanto c'è sul conto", @"il mio saldo",
			@"il saldo del conto", @"quanto ho speso", @"quanto mi resta sul conto",
			@"il mio stipendio", @"la mia bolletta", @"la mia carta di credito",
			@"quanti soldi ho", @"my bank balance", @"how much money do i have",
			@"how much have i spent", @"mon solde", @"mi saldo",
			@"cuánto dinero tengo",],

		/* The markets, which are not on this Mac either. */
		@[@"markets",
			@"I cannot see the markets.",
			@"quanto vale in borsa", @"vale in borsa", @"quotazione di",
			@"quanto vale apple", @"il prezzo delle azioni", @"quanto è salito il titolo",
			@"quanto vale il bitcoin", @"il cambio euro dollaro",
			@"stock price", @"share price", @"how much is apple worth",
			@"cours de l'action", @"precio de las acciones"],

		/* Mail, messages, calls. */
		@[@"mail",
			@"I cannot see your mail.",
			@"chi mi ha scritto", @"chi mi ha cercato", @"messaggi non letti",
			@"mail non lette", @"email non lette", @"quante mail ho",
			@"la mia posta", @"le mie notifiche", @"chiamate perse",
			@"chi mi ha chiamato", @"ho ricevuto messaggi",
			@"who wrote to me", @"unread messages", @"unread mail", @"my inbox",
			@"missed calls", @"ma boîte", @"mes messages non lus",
			@"mi correo", @"mensajes sin leer"],

		/* What is inside a file — unless a folder was handed over. */
		@[@"files",
			@"I cannot see inside your files.",
			@"cosa c'è nel file", @"cosa c'è scritto nel file",
			@"cosa c'è nel documento", @"cosa contiene il file",
			@"dove ho salvato", @"quanto pesa il file", @"cosa ho scritto nel file",
			@"what's in the file", @"what is in the file", @"where did i save",
			@"qu'y a-t-il dans le fichier", @"qué hay en el archivo"],

		/* Whether the work works. */
		@[@"build",
			@"I cannot see whether it builds.",
			@"il mio codice compila", @"il codice compila", @"la build è finita",
			@"la build è passata", @"il test passa", @"i test passano",
			@"ci sono errori di compilazione", @"la compilazione è finita",
			@"does my code compile", @"did the build pass", @"do the tests pass",
			@"est-ce que ça compile", @"compila mi código"],

		/* Other people. */
		@[@"people",
			@"I cannot see who is there.",
			@"chi è al telefono", @"chi ha suonato", @"chi c'è alla porta",
			@"come si chiama il mio collega", @"come si chiama mia",
			@"chi è quella persona", @"chi c'è in riunione",
			@"who is on the phone", @"who is at the door",
			@"what's my colleague called", @"qui est au téléphone",
			@"quién está al teléfono"],

		/* The weather, which is the world rather than the Mac — and which
		   NekoWeb takes first whenever it can actually answer: a place named in
		   the question, or the town this Mac is in. This only ever speaks for
		   what is left, which is the ordering the whole class relies on.

		   The bare present tense used to be missing. "che tempo fa a Vicenza"
		   was here and "che tempo fa" was not, so on a Mac that has not been
		   told where it is — which is every Mac until somebody grants the
		   location — the commonest phrasing of all went past NekoWeb, past this,
		   and into a model with no forecast in front of it. tests/reach.m found
		   it: that question is in this Mac's own diary twice. Each entry below
		   is now the shortest form NekoWeb also recognises, so the two lists
		   cannot drift apart again. */
		@[@"weather",
			@"I cannot see the weather.",
			@"che tempo fa", @"che tempo farà", @"che tempo c",
			@"piove", @"pioverà", @"che temperatura c'è", @"quanti gradi",
			@"previsioni", @"meteo",
			@"what's the weather", @"what is the weather", @"how's the weather",
			@"how is the weather", @"will it rain", @"how many degrees",
			@"quel temps", @"la météo", @"combien de degrés",
			@"qué tiempo", @"que tiempo", @"cuántos grados",
			/* Not the weather: tempo is also time, and these are time. */
			@"!tempo fa che", @"!quanto tempo fa", @"!da quanto tempo",
			@"!piove sul bagnato"],

		/* And what is in a calendar this application can write to and not read. */
		@[@"calendar",
			@"I cannot see your calendar.",
			@"cosa ho in calendario", @"che impegni ho", @"ho appuntamenti",
			@"che appuntamenti ho", @"cosa ho domani in calendario",
			@"quando ho la riunione", @"a che ora ho l'appuntamento",
			@"what's on my calendar", @"what do i have tomorrow",
			@"mon agenda", @"mi agenda"],

		/* And the person's own body and night. */
		@[@"body",
			@"I cannot know that about you.",
			@"cosa ho sognato", @"quanto ho dormito", @"come ho dormito",
			@"quanti passi ho fatto", @"quanto ho camminato", @"il mio battito",
			@"quanto peso", @"la mia pressione",
			@"what did i dream", @"how did i sleep", @"how many steps",
			@"qu'ai-je rêvé", @"qué soñé", @"cuánto dormí"],
	];
	
	return classes;
}

@implementation NekoUnseen

+ (NSString *)wantedFor:(NSString *)question
{
	NSString *text = [question lowercaseString];
	NSEnumerator *groups = [NekoUnseenClasses() objectEnumerator];
	NSArray *group;
	for(NSArray<NSString*> *group in NekoUnseenClasses()) {
		NSString *kind = [group objectAtIndex:0];

		/* A folder somebody handed over in a panel is a folder this application
		   can read. It does not get to say it cannot see inside files while it
		   has a bookmark to one. */
		if([kind isEqualToString:@"files"]
		   && [[[NekoFolderAccess sharedAccess] allowedKeys] count] > 0)
			continue;

		/* A phrase written with a leading "!" is the other kind: it does not
		   claim the question, it stops this class claiming it.

		   Needed the moment a phrase got short enough to be useful, because a
		   short phrase in one language is a different sentence in another part
		   of the same one. "che tempo fa" is the weather; "che tempo fa che non
		   ci vediamo" is how long it has been — same three words, and
		   tests/unseen.m caught it within a minute of the list being widened. A
		   veto keeps the entries short instead of forcing every phrasing to be
		   enumerated, which is the thing this file is bad at. */
		NSUInteger i;
		BOOL vetoed = NO;
		for(i = 2; i < [group count] && !vetoed; i++) {
			NSString *phrase = [group objectAtIndex:i];
			if([phrase hasPrefix:@"!"]
			   && [text rangeOfString:[phrase substringFromIndex:1]].location
			      != NSNotFound)
				vetoed = YES;
		}
		if(vetoed)
			continue;

		for(i = 2; i < [group count]; i++) {
			NSString *phrase = [group objectAtIndex:i];
			if([phrase hasPrefix:@"!"])
				continue;
			if([text rangeOfString:phrase].location != NSNotFound)
				return NekoUnseenLocalized([group objectAtIndex:1]);
		}
	}
	return nil;
}

@end
