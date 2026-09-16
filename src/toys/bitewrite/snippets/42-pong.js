// name: pong
// about: a game — your paddle follows the mouse (or hold ↑ ↓), first to 5 wins
// level: game
let pw = 14, ph = 110, you = H / 2, cpu = H / 2
let ball, me = 0, it = 0, lastY = -1, moved = -9

function serve(dx) {
  ball = { x: W / 2, y: H / 2, vx: 7 * dx, vy: (rand() - 0.5) * 8 }
}
serve(1)

function onKey(k) {
  if (k === "space" && (me >= 5 || it >= 5)) { me = 0; it = 0; serve(1) }
}

function frame(t) {
  if (keys.up) you -= 10
  if (keys.down) you += 10
  if (mouse.y !== lastY) { lastY = mouse.y; moved = t }
  if (t - moved < 1) you += (mouse.y - you) * 0.3
  you = max(ph / 2, min(H - ph / 2, you))
  cpu += (ball.y - cpu) * 0.07

  if (me < 5 && it < 5) {
    ball.x += ball.vx
    ball.y += ball.vy
    if (ball.y < 10) { ball.y = 10; ball.vy = abs(ball.vy) }
    if (ball.y > H - 10) { ball.y = H - 10; ball.vy = -abs(ball.vy) }
    if (ball.vx < 0 && ball.x < 40 && abs(ball.y - you) < ph / 2) {
      ball.vx = -ball.vx * 1.05
      ball.vy += (ball.y - you) * 0.15
    }
    if (ball.vx > 0 && ball.x > W - 40 && abs(ball.y - cpu) < ph / 2) {
      ball.vx = -ball.vx * 1.05
      ball.vy += (ball.y - cpu) * 0.1
    }
    if (ball.x < 0) { it++; serve(1) }
    if (ball.x > W) { me++; serve(-1) }
  }

  ctx.fillStyle = "black"
  ctx.fillRect(0, 0, W, H)
  ctx.fillStyle = "#333"
  for (let y = 0; y < H; y += 30) ctx.fillRect(W / 2 - 2, y, 4, 16)
  ctx.fillStyle = ACCENT
  ctx.fillRect(20, you - ph / 2, pw, ph)
  ctx.fillStyle = "white"
  ctx.fillRect(W - 20 - pw, cpu - ph / 2, pw, ph)
  ctx.beginPath()
  ctx.arc(ball.x, ball.y, 9, 0, PI * 2)
  ctx.fill()
  ctx.font = "bold 48px monospace"
  ctx.fillText(me, W / 2 - 80, 70)
  ctx.fillText(it, W / 2 + 50, 70)
  if (me >= 5 || it >= 5) {
    ctx.font = "bold 32px monospace"
    ctx.fillText((me >= 5 ? "you win" : "the machine wins") + " — space for another", W / 2 - 330, H / 2)
  }
}
