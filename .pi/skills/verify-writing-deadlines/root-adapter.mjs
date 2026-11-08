import vm from 'node:vm';

// Executes the actual bridge, the actual data-on expressions and the actual
// editor listeners. It does not implement the timer rules, and it does not
// render: the fake document only satisfies the DOM calls the transition paths
// make (the trial editor rewrite after a wipe, caret placement, focus).
//
// An expression is compiled as a FUNCTION BODY, the way Datastar compiles it
// (`Function("el", "$", "__action", "evt", ..., body)`), so `const`/`let`
// declarations inside an expression are legal here exactly as they are in the
// browser. Globals such as `evt` and `$_session` resolve from the context.
export function rootAdapter(html) {
  const module = html.match(/<script type="module">([\s\S]*?)<\/script>/)?.[1];
  if (!module?.includes('window.FirstLineLandingDemo')) throw new Error('Root bridge moved; review adapter.');
  const exposed = module.replace('    bind,', '    bind, bindSessionEditor,');
  if (exposed === module) throw new Error('Cannot expose editor binding; review adapter.');
  const initial = JSON.parse(html.match(/data-signals='([^']+)'/)[1])._session;
  const handlers = new Map([...html.matchAll(/data-on:(fl\w+)="([^"]+)"/g)].map(([, name, expression]) => {
    const body = expression.replaceAll('&amp;', '&').replaceAll('&gt;', '>').replaceAll('&lt;', '<');
    const compiled = new vm.Script(`(function () {\n${body}\n})`);
    return [name, () => compiled.runInContext(context)()];
  }));
  let now = 100000;
  const listeners = new Map();
  const editor = {
    innerText: '', textContent: '', isContentEditable: true,
    addEventListener: (name, fn) => listeners.set(name, fn),
    focus() {},
    classList: { add() {}, remove() {}, contains: () => false },
  };
  const context = vm.createContext({
    Date: { now: () => now }, Intl, console,
    window: { getSelection: () => ({ removeAllRanges() {}, addRange() {} }) },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
    document: {
      readyState: 'loading', addEventListener() {},
      createRange: () => ({ selectNodeContents() {}, collapse() {} }),
      querySelector: selector => selector === '.trial-editor' ? editor : null,
      body: {
        classList: { contains: name => name === 'trial-mode' && context.$_session.context === 'trial' },
        dispatchEvent(event) {
          const handler = handlers.get(event.type);
          if (!handler) throw new Error(`Missing signal handler: ${event.type}`);
          context.evt = event;
          handler();
        },
      },
    },
  });
  new vm.Script(exposed).runInContext(context);
  const bridge = context.window.FirstLineLandingDemo;
  // In the browser a window property is also a bare global, and the expressions
  // call `FirstLineLandingDemo.*`. The context's `window` is a plain object, so
  // publish the same object as a global here.
  context.FirstLineLandingDemo = bridge;
  bridge.bindSessionEditor(editor);
  function reset() {
    context.$_session = structuredClone(initial);
    context.$_session.context = 'trial';
    editor.innerText = '';
  }
  // The browser writes the new text into the contenteditable, then fires input.
  function input(value, time) {
    now = time;
    editor.innerText = value;
    listeners.get('input')();
  }
  function tick(time) {
    now = time;
    const s = context.$_session;
    bridge.tickDispatch(s.active, s.failed, s.complete, s.context, s.startedAt, s.lastInputAt, s.duration, s.text);
  }
  return {
    reset, input, tick,
    get state() { return context.$_session; },
    snapshot() { return structuredClone(context.$_session); },
    restore(state) { context.$_session = structuredClone(state); },
  };
}
