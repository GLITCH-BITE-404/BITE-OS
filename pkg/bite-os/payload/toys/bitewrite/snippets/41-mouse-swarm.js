// name: mouse swarm
// about: a cloud of sparks that chases your mouse — click to scatter it
// level: game
let ps = []
for (let i = 0; i < 300; i++)
  ps.push({ x: rand() * W, y: rand() * H, vx: 0, vy: 0 })

function onClick(mx, my) {
  for (let p of ps) {
    let a = rand() * PI * 2
    p.vx = cos(a) * 20
    p.vy = sin(a) * 20
  }
}

function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.15)"
  ctx.fillRect(0, 0, W, H)
  for (let p of ps) {
    p.vx += (mouse.x - p.x) * 0.002 + (rand() - 0.5)
    p.vy += (mouse.y - p.y) * 0.002 + (rand() - 0.5)
    p.vx *= 0.96
    p.vy *= 0.96
    p.x += p.vx
    p.y += p.vy
    ctx.fillStyle = hsl(hypot(p.vx, p.vy) * 30 + t * 40, 90, 60)
    ctx.fillRect(p.x, p.y, 3, 3)
  }
}
