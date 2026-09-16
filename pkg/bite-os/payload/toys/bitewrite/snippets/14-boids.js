// name: boids
// about: a flock that steers itself — keep apart, line up, stay together
// level: extreme
let N = 70, b = []
for (let i = 0; i < N; i++)
  b.push({ x: rand() * W, y: rand() * H, vx: rand() * 4 - 2, vy: rand() * 4 - 2 })

function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.2)"
  ctx.fillRect(0, 0, W, H)
  for (let p of b) {
    let ax = 0, ay = 0, cx = 0, cy = 0, sx = 0, sy = 0, n = 0
    for (let q of b) {
      let dx = q.x - p.x, dy = q.y - p.y, d = dx * dx + dy * dy
      if (q === p || d > 6400) continue
      n++; cx += q.x; cy += q.y; ax += q.vx; ay += q.vy
      if (d < 600) { sx -= dx; sy -= dy }
    }
    if (n) {
      p.vx += (ax / n - p.vx) * 0.05 + (cx / n - p.x) * 0.002 + sx * 0.02
      p.vy += (ay / n - p.vy) * 0.05 + (cy / n - p.y) * 0.002 + sy * 0.02
    }
    let s = sqrt(p.vx * p.vx + p.vy * p.vy)
    if (s > 4) { p.vx *= 4 / s; p.vy *= 4 / s }
    p.x = (p.x + p.vx + W) % W
    p.y = (p.y + p.vy + H) % H
    ctx.fillStyle = hsl(atan2(p.vy, p.vx) * 57 + 180, 90, 60)
    ctx.beginPath()
    ctx.arc(p.x, p.y, 4, 0, PI * 2)
    ctx.fill()
  }
}
