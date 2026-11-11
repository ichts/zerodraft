/*
 * [INPUT]: AppKit's window ordering and NSButtonCell click paths, exercised by the Swift tests.
 * [OUTPUT]: A test process whose window animations are off and whose button clicks never run a nested event loop.
 * [POS]: Loaded with the test bundle, before any test creates a window or clicks a button. Not part of the app.
 * [PROTOCOL]: Keep every process-level change the tests need in this file, with the failure it prevents.
 *
 * The failure both fixes prevent: the Swift test runner sits in CFRunLoopRun on the main thread
 * (swift_task_asyncMainDrainQueue). AppKit posts a CFRunLoopStop that it meant for its own nested loop;
 * if the nested loop ended some other way the stop stays queued, and it lands on the runner's loop. The runner
 * then returns and the process exits 0 mid-run: most tests never run and there is no summary line.
 * Reproduced with `BeginLatencyTests` followed by any test that orders a window in, and with the Return-key
 * tests; `scripts/swift-test-gate.py` is what turns that silent exit into a failure.
 *
 *  1. Window animations off. Ordering a window in starts _NSWindowTransformAnimation, which stops the run loop
 *     when it finishes.
 *  2. -[NSButtonCell performClick:] without the nested loop. AppKit's version spins
 *     nextEventMatchingMask:untilDate: to show the pressed state, and that loop leaves the stray stop. The
 *     replacement does what a click does to the model: the next state, then the action to the target. It is
 *     reached by NSButton.performClick(_:) and by NSButton's key-equivalent path, so the tests still drive the real
 *     Return and click routes.
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void WIDDisableWindowAnimations(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *arguments = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    arguments[@"NSAutomaticWindowAnimationsEnabled"] = @NO;
    [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
}

@interface NSButtonCell (WIDTestClick)
- (void)wid_performClick:(id)sender;
@end

@implementation NSButtonCell (WIDTestClick)
- (void)wid_performClick:(id)sender {
    NSControl *control = (NSControl *)self.controlView;
    if (!self.isEnabled || ![control isKindOfClass:NSControl.class]) return;
    [self setNextState];
    [control sendAction:self.action to:self.target];
}
@end

static void WIDReplaceButtonClick(void) {
    Method original = class_getInstanceMethod(NSButtonCell.class, @selector(performClick:));
    Method replacement = class_getInstanceMethod(NSButtonCell.class, @selector(wid_performClick:));
    method_exchangeImplementations(original, replacement);
}

__attribute__((constructor)) static void WIDHardenTestProcess(void) {
    WIDDisableWindowAnimations();
    WIDReplaceButtonClick();
}
