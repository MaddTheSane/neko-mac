//
//  NekoAntics2.swift
//  Neko
//
//  Created by C.W. Betts on 9/19/26.
//

import Cocoa

/* How often it considers being curious, and how long it waits between antics.
   Often enough to feel alive, rare enough not to be a colleague who taps you on
   the shoulder every minute. */
private let NekoAnticsHeartbeat: TimeInterval = 5.0;
private let NekoAnticsMinWait: TimeInterval = 90.0;
private let NekoAnticsWaitSpread: TimeInterval = 150.0;

/// Nobody there.
private let NekoAnticsAway: TimeInterval = 150.0;

/// An arm's length for a cat: near enough to be nosy, far enough not to be on the
/// caret. Varied through the pink-noise stream so it is not the same spot twice.
private let NekoAnticsNear: CGFloat = 60.0
/// An arm's length for a cat: near enough to be nosy, far enough not to be on the
/// caret. Varied through the pink-noise stream so it is not the same spot twice.
private let NekoAnticsFar: CGFloat  = 90.0

/// And off the line it walked in on, by this much: 40 to 70 degrees puts it
/// beside the thing rather than in front of it.
private let NekoAnticsSideMin: CGFloat = 40.0
/// And off the line it walked in on, by this much: 40 to 70 degrees puts it
/// beside the thing rather than in front of it.
private let NekoAnticsSideMax: CGFloat = 70.0

/// The curious half of roaming.
///
/// Wandering from place to place is what the cat does; this is what makes it
/// look interested in you. Every so often it drops what it was doing, comes over
/// to the pointer and asks what you are writing, or pounces on the cursor, or
/// goes to claw the edge of the screen.
///
/// What it goes on comes from NekoDesktop: counters the system hands out with no
/// permission at all — keys and mouse moves since boot, seconds since the last
/// one — plus, if that switch is on, the text being worked on.

/// What it says comes from whichever engine Ask Neko is set to, asked while the
/// cat is still walking over, with written-in lines as the fallback for when
/// there is no engine or it does not answer in time.
@objc
public final class NekoAntics2 : NSObject {
	private var heartbeat: Timer?
	/// watches for the cat reaching the pointer
	private var arrival: Timer?
	
	private var lastAntic: Date?
	/// seconds until it is allowed to be curious
	private var cooldown: TimeInterval
	/// what it will say once it arrives
	private var pendingLine: String?

	@objc(sharedAntics)
	public static let shared = NekoAntics2()

	private override init() {
		cooldown = NekoAnticsMinWait
		super.init()
		NotificationCenter.default.addObserver(self,
											   selector: #selector(self.settingsChanged(note:)),
											   name: .NekoSettingsDidChange,
											   object: nil)
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
		heartbeat?.invalidate()
		arrival?.invalidate()
	}
	
	@objc private func settingsChanged(note: Notification) {
		applySettings()
	}
	
	/// Runs in the roaming behaviour and stops in the other two. Safe to call
	/// whenever the settings change.
	@objc public func applySettings() {
		let wanted = NekoController.shared.roamsOnItsOwn
		if wanted == (heartbeat != nil) {
			return
		}
		if !wanted {
			heartbeat?.invalidate()
			heartbeat = nil
			arrival?.invalidate()
			arrival = nil
			return
		}
		heartbeat = Timer.scheduledTimer(timeInterval: NekoAnticsHeartbeat,
										 target: self,
										 selector: #selector(self.consider(_:)),
										 userInfo: nil,
										 repeats: true)
	}

	// MARK: What the machine will admit to

	/// Everything the antics run on comes from NekoDesktop, which the suggestions
	/// read too.
	private var idleSeconds: TimeInterval {
		return NekoDesktop.shared.idleSeconds
	}

	// MARK: - Deciding

	private func mayBeCuriousNow() -> Bool {
		let controller = NekoController.shared
		let panel = controller?.panel
		guard let panel, let controller else {
			return false
		}
		guard panel.isRoaming && !controller.isPaused else {
			return false
		}
		if panel.isOnErrand || panel.isHeld {
			return false
		}
		guard NekoAsk.shared.canSpeakUnprompted() else {
			return false
		}
		if idleSeconds > NekoAnticsAway {
			return false
		}
		if NekoDesktop.shared.isBusyElsewhere {
			return false /* a film, a presentation, a password field */
		}
		return lastAntic == nil || -(lastAntic!.timeIntervalSinceNow) > cooldown
	}

	@objc private func consider(_ timer: Timer) {
		NekoDesktop.shared.sample()
		guard mayBeCuriousNow() else {
			return
		}
		anticNow()
	}
	
	// MARK: - The antics themselves
	
	private func questionsAboutTyping() -> String {
		let lines = [
			NSLocalizedString("What are you writing?", comment: "What are you writing?"),
			NSLocalizedString("Is it about me?", comment: "Is it about me?"),
			NSLocalizedString("That is a lot of words. Any of them mine?", comment: "That is a lot of words. Any of them mine?"),
			NSLocalizedString("May I watch you type?", comment: "May I watch you type?"),
			NSLocalizedString("Need a hand? I only have paws.", comment: "Need a hand? I only have paws.")]
		
		return lines.randomElement()!
	}
	
	private func lineAboutThePointer() -> String {
		let lines = [
			NSLocalizedString("Got it. It was getting away.", comment: "Got it. It was getting away."),
			NSLocalizedString("This arrow keeps moving. Suspicious.", comment: "This arrow keeps moving. Suspicious."),
			NSLocalizedString("Caught your cursor. You may have it back.", comment: "Caught your cursor. You may have it back.")];
		
		return lines.randomElement()!
	}
	
	/// Where to stand when it comes over to be nosy: beside whatever it is looking
	/// at rather than on top of it, and off the line it walked in on.
	///
	/// People keep a distance from an agent that attends to them, and the closer and
	/// more head-on the attention, the more they compensate --- measured with robots,
	/// and the same instinct applies to a cat that lands on the caret. So the spot is
	/// an arm's length away and to one side. Public because the geometry is worth
	/// testing without a screen.
	///
	/// Typing fast is what sends it over in the first place, so it may well still be
	/// happening when it arrives: this is the number that decides whether it says
	/// anything or thinks better of it and leaves.
	@objc(spotBesidePoint:fromCatAtPoint:withinBounds:)
	public func spotBeside(_ what: NSPoint, from cat: NSPoint, within bounds: NSRect) -> NSPoint {
		#if USE_NEKONOISE
		let noise = NekoNoise.shared!
		let radius = NekoAnticsNear + noise.next() * (NekoAnticsFar - NekoAnticsNear)
		var side = NekoAnticsSideMin + noise.next() * (NekoAnticsSideMax - NekoAnticsSideMin)
		if noise.next() < 0.5 {
			/* either side of the approach */
			side = -side
		}
		#else
		let radius = CGFloat.random(in: NekoAnticsNear ..< NekoAnticsFar)
		var side = CGFloat.random(in: NekoAnticsSideMin ..< NekoAnticsSideMax)
		if Bool.random() {
			/* either side of the approach */
			side = -side
		}
		#endif
		
		/* The direction it came from, turned by that much. */
		var dx = what.x - cat.x, dy = what.y - cat.y;
		var length = sqrt(dx * dx + dy * dy)
		if length < 1.0 {
			dx = 1.0
			dy = 0.0
			length = 1.0
		}
		let angle: CGFloat = atan2(dy, dx) + side * CGFloat.pi / 180.0
		
		/* Measured back from the thing toward where the cat is coming from, so the
		   spot ends up beside it on the near side rather than beyond it. */
		var spot = NSPoint(x: what.x - cos(angle) * radius,
						   y: what.y - sin(angle) * radius)
		/* On screen, and not so clamped that it lands on the thing anyway. */
		spot.x = min(max(spot.x, bounds.minX + 16.0), bounds.maxX - 16.0)
		spot.y = min(max(spot.y, bounds.minY + 16.0), bounds.maxY - 16.0)
		
		return spot
	}
	
	/// Where the cat should stand to be nosy: beside the pointer, which is where the
	/// caret usually is and, more to the point, where you are looking.
	private func pointerSpot() -> NSPoint {
		let pointer = NSEvent.mouseLocation
		guard let panel = NekoController.shared.panel else {
			return pointer
		}
		
		let frame = panel.frame
		return spotBeside(pointer,
						  from: NSPoint(x: frame.midX, y: frame.minY),
						  within: panel.nekoScreenBounds())
	}
	
	/// It came over because somebody was typing hard, and somebody typing hard when
	/// it arrives has not stopped for it. Then the polite thing is the thing a
	/// colleague does: notice, and not say it.
	@objc public var shouldWithdrawInstead: Bool {
		return NekoDesktop.shared.keysPerMinute > 40
	}
	
	/// The walk covers the latency: the cat sets off at once and the model is asked
	/// while it crosses the desk, so a question that takes a second to write arrives
	/// just as the cat sits down. If no engine is set up, or it fails, or it takes
	/// longer than the walk plus a moment, the written-in line is used instead — the
	/// antic still happens, which matters more than which words it ends with.
	private func askForLineInsteadOf(_ fallback: String) {
		/* Same rule as the suggestions: on this Mac, and good enough to be worth
		   hearing. When neither holds, the written-in line stays. */
		guard let provider = NekoBrains.bestOnDeviceProvider(), provider.isConfigured else {
			return
		}
		
		guard let character = NekoController.shared.character else {
			return
		}
		let instructions = NekoCuriosityInstructionsFor(character.persona)
		let context = NekoDesktop.shared.summary()!
		let asked = Date()
		
		provider.askQuestion(context, instructions: instructions) { [self] answer, error in
			/* Only if this antic is still the one in progress: a slow answer that
			   arrives after the cat has wandered off is a line nobody asked for. */
			guard let lastAntic, var line = answer else {
				return
			}
			if lastAntic.compare(asked) == .orderedDescending {
				return
			}
			
			cleanUp(&line)
			/* A question that came out badly leaves the written-in one in place,
			   which is why pendingLine was set before asking. */
			guard NekoSense.isWorthSaying(line) else {
				return
			}
			self.pendingLine = line
		}
	}
	
	private func beginAntic(_ line2: String?, goingTo spot: NSPoint, pose: NekoState, forTicks ticks: UInt32) {
		var line = line2
		/* The walk is not an interruption; the sentence is. Inside the quiet period
		   the cat still comes over, sits down and looks at you, and then goes away
		   again without saying anything — which is most of the charm and none of the
		   nagging. */
		if !NekoAsk.mayInterruptNow() {
			line = nil
		}
		
		let panel = NekoController.shared.panel!
		lastAntic = Date()
		cooldown = NekoAnticsMinWait + TimeInterval.random(in: 0 ..< NekoAnticsWaitSpread)
		
		pendingLine = line
		panel.errand(to: spot, thenState: pose, forTicks: ticks)
		if let line {
			askForLineInsteadOf(line)
		}
		
		/* The line waits for the cat: saying "what are you writing?" from the other
		   side of the screen is a different, worse joke. */
		arrival?.invalidate()
		arrival = nil;
		if pendingLine != nil {
			arrival = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.sayItThere(_:)), userInfo: nil, repeats: true)
		}
	}
	
	@objc private func sayItThere(_ timer: Timer) {
		guard let panel = NekoController.shared.panel, panel.isRoaming else {
			arrival?.invalidate()
			arrival = nil
			return
		}
		
		guard !panel.isOnErrand else {
			return /* still on its way */
		}
		
		arrival?.invalidate()
		arrival = nil
		
		if let pendingLine, !pendingLine.isEmpty, shouldWithdrawInstead {
			/* It came over, saw the typing had not stopped, and went away without
			   saying anything. Nothing is spoken, so nothing counts against the
			   day's remarks either — this was a visit, not an interruption. */
			self.pendingLine = nil;
			withdrawFrom(NSEvent.mouseLocation)
			return
		}
		
		if let pendingLine {
			NekoAsk.shared.sayUnprompted(pendingLine)
		}
		pendingLine = nil
	}
	
	/* Which antic suits the moment. Typing hard is the interesting one — that is
	   somebody at work, and a cat that came over to read it is the joke. */
	/// Away from whatever it came to look at, far enough that it reads as leaving.
	private func withdrawFrom(_ what: NSPoint) {
		guard let panel = NekoController.shared.panel else {
			return
		}
		
		let frame = panel.frame
		let here = NSPoint(x: frame.midX, y: frame.minY)
		var dx = here.x - what.x, dy = here.y - what.y;
		var length = sqrt(dx * dx + dy * dy)
		if length < 1.0 {
			dx = -1.0
			dy = 0.0
			length = 1.0
		}
		let bounds = panel.nekoScreenBounds()
		var away = NSMakePoint(here.x + dx / length * 140.0,
							   here.y + dy / length * 140.0)
		away.x = min(max(away.x, bounds.minX + 16.0), bounds.maxX - 16.0)
		away.y = min(max(away.y, bounds.minY + 16.0), bounds.maxY - 16.0)
		panel.errand(to: away, thenState: .stop, forTicks: 8)

	}
	
	/// One antic now, whatever the timers think --- the preferences use it so the
	/// thing can be watched once instead of waited for. Returns what it decided to
	/// do, for the status line.
	@discardableResult
	@objc public func anticNow() -> String {
		NekoDesktop.shared?.sample()
		guard let panel = NekoController.shared.panel, panel.isRoaming else {
			return NSLocalizedString("Only while roaming.", comment: "Only while roaming.")
		}
		
		let desktop = NekoDesktop.shared!
		let idle = desktop.idleSeconds
		
		if desktop.keysPerMinute > 40 {
			/* Reading over your shoulder: it comes over, sits, and asks. */
			beginAntic(questionsAboutTyping(), goingTo: pointerSpot(), pose: .kaki, forTicks: 40)
			return NSLocalizedString("It came over to ask what you are writing.", comment: "It came over to ask what you are writing.")
		}
		
		if desktop.movesPerMinute > 120 {
			/* The one antic that is supposed to land on the pointer: pouncing beside
			   the cursor is not pouncing. */
			beginAntic((arc4random_uniform(2) == 0) ? lineAboutThePointer() : nil,
					   goingTo: NSEvent.mouseLocation,
					   pose: .kaki,
					   forTicks: 16)
			return NSLocalizedString("It pounced on the cursor.", comment: "It pounced on the cursor.");
		}
		
		if idle > 20.0 {
			/* Nobody typing, nobody clicking: it goes and claws the edge of the
			   screen, which the wall behaviour turns into scratching on arrival. */
			/* The panel's own accessor and not the window's screen: a window on no
			   display answers nil, nil answers an empty rectangle, and this then
			   works out the edge of the screen from a rectangle at the origin —
			   sending the cat to x = 0 from wherever it was standing. With a
			   portrait monitor above a laptop that is reachable, and it is what
			   "the cat goes mad along the borders" turned out to be. */
			let bounds = panel.nekoScreenBounds()
			let frame = panel.frame
			let left = NSMidX(frame) < NSMidX(bounds)
			beginAntic(nil,
					   goingTo: NSPoint(x: left ? bounds.minX : bounds.maxX,
										y: frame.minY),
					   pose: .count,
					   forTicks: 0)
			return NSLocalizedString("It went to claw the edge of the screen.", comment: "It went to claw the edge of the screen.");
		}

		/* Something is happening, just not much: a look in your direction. */
		beginAntic(nil,
				   goingTo: pointerSpot(),
				   pose: .jare,
				   forTicks: 24)
		return NSLocalizedString("It wandered over to see what you were up to.", comment: "It wandered over to see what you were up to.");
	}
}

/// Small models bold their one sentence or wrap it in quotation marks, which
/// inside a speech bubble reads as somebody quoting somebody else.
private func cleanUp(_ answer: inout String) {
	var line = answer
	if #available(macOS 13.0, *) {
		line.replace("**", with: "")
		line.replace("*", with: "")
		line.replace("#", with: "")
	} else {
		line = line.replacingOccurrences(of: "**", with: "")
		line = line.replacingOccurrences(of: "*", with: "")
		line = line.replacingOccurrences(of: "#", with: "")
	}
	if let stop = line.range(of: "\n") {
		line = String(line[line.startIndex ..< stop.lowerBound])
	}
	answer = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'\u{201c}\u{201d}\u{00ab}\u{00bb}"))
}
