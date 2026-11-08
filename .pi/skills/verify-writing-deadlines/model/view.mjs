export const title = '写作会话最短违规路径';
export function state(v) {
  const p = { Root: '根网页', Web: '试用网页', Mac: 'Mac' }[v.surface];
  if (v.event === 'input' && v.expected === 'wipe' && v.text.includes('old')) return `${p} 已过删除线却保住旧稿`;
  if (v.event === 'input' && v.expected === 'keep' && v.phase !== 'kept') return `${p} 已到零点却仍可追加`;
  if (v.surface === 'Root' && v.event === 'tick' && v.expected === 'wipe' && v.receipt !== Math.max(0, v.started + 60 - v.last - 8)) return `${p} 删除收据少算未用时间`;
  return `${p} ${{home:'入口',empty:'空房间',writing:'写作中',warn:'静默警告',wiped:'已删除',kept:'已保留',left:'已离开',locked:'需激活',restarted:'可重新开写'}[v.phase]}`;
}
export function step(action, from, to) {
  if (action === 'InputAt') return `第 ${to.now} 秒输入`;
  if (action === 'TickAt') return `第 ${to.now} 秒时钟回调`;
  return {Enter:'进入房间或被拦住',FirstInput:'输入首字',InputAt:'输入到达',TickAt:'时钟回调',Delete:'尝试删除',Escape:'按退出',ExpireExit:'确认超时',Restart:'重新开始',Done:'结束'}[action] ?? action;
}
