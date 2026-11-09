export const title = '写作会话的三个结局';
export function state(v) {
  const p = { Root: '网页', Web: 'writeitdown 网页', Mac: 'Mac 应用' }[v.surface];
  const phase = { home:'入口', empty:'空房间', writing:'写作中', warn:'静默警告', wiped:'已删除', kept:'已保留', left:'已离开', locked:'需激活', restarted:'等下个字' }[v.phase];
  return `${p} ${phase}`;
}
export function step(action, from, to) {
  if (action === 'InputAt') {
    if (to.expected === 'wipe') return '删除线过后又输入';
    if (to.expected === 'keep') return '到点后又输入';
    return '输入一个字';
  }
  if (action === 'TickAt') {
    if (to.expected === 'wipe') return '安静满八秒';
    if (to.expected === 'keep') return '写满一分钟';
    return to.phase === 'warn' ? '安静满五秒' : '时钟还在走';
  }
  return {Enter:'进入房间或被拦住',FirstInput:'输入首字',InputAt:'输入到达',TickAt:'时钟回调',Delete:'尝试删除',Escape:'按退出',ExpireExit:'确认超时',Restart:'下一个字就是新稿',BeginAgain:'再次开写',Done:'结束'}[action] ?? action;
}
