// name: matrix rain
// about: code falling down the screen, the classic
// level: easy
let size = 18
let cols = floor(W / size)
let drops = []
for (let i = 0; i < cols; i++) drops.push(rand() * -40)
function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.08)"
  ctx.fillRect(0, 0, W, H)
  ctx.fillStyle = ACCENT
  ctx.font = size + "px monospace"
  for (let i = 0; i < cols; i++) {
    ctx.fillText(pick("01<>/{}[]=+*#$"), i * size, drops[i] * size)
    if (drops[i] * size > H && rand() > 0.97) drops[i] = 0
    drops[i]++
  }
}
