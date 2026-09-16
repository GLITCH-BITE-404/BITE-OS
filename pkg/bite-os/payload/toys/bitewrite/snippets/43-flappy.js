// name: flappy dot
// about: a game — space or click to flap through the gaps
// level: game
let y, vy, pipes, score, dead, best = 0, spawn = -9

function reset() {
  y = H / 2
  vy = 0
  pipes = []
  score = 0
  dead = false
}
reset()

function flap() {
  if (dead) reset()
  else vy = -9
}
function onKey(k) { if (k === "space" || k === "up" || k === "w") flap() }
function onClick(mx, my) { flap() }

function frame(t) {
  if (!dead) {
    vy += 0.5
    y += vy
    if (t - spawn > 1.6) {
      spawn = t
      pipes.push({ x: W, gap: 120 + rand() * (H - 360), passed: false })
    }
    for (let p of pipes) {
      p.x -= 4
      if (!p.passed && p.x + 60 < 84) { p.passed = true; score++; best = max(best, score) }
      let inside = p.x < 116 && p.x + 60 > 84
      if (inside && (y - 16 < p.gap || y + 16 > p.gap + 200)) dead = true
    }
    pipes = pipes.filter(p => p.x > -80)
    if (y > H || y < 0) dead = true
  }
  ctx.fillStyle = "#0b1020"
  ctx.fillRect(0, 0, W, H)
  ctx.fillStyle = ACCENT
  for (let p of pipes) {
    ctx.fillRect(p.x, 0, 60, p.gap)
    ctx.fillRect(p.x, p.gap + 200, 60, H)
  }
  ctx.fillStyle = dead ? "#ff5555" : "#ffd84d"
  ctx.beginPath()
  ctx.arc(100, y, 16, 0, PI * 2)
  ctx.fill()
  ctx.fillStyle = "white"
  ctx.font = "bold 28px monospace"
  ctx.fillText("score " + score + "   best " + best, 20, 40)
  if (dead) ctx.fillText("ouch — space to try again", W / 2 - 200, H / 2)
}
