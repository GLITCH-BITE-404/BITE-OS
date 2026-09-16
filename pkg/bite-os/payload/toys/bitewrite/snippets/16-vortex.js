// name: vortex
// about: particles spiralling down a glowing drain
// level: medium
let ps = []
for (let i = 0; i < 500; i++) ps.push({ a: rand() * PI * 2, r: rand() * W / 2 })

function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.12)"
  ctx.fillRect(0, 0, W, H)
  for (let p of ps) {
    p.a += 30 / (p.r + 20)
    p.r -= 0.6
    if (p.r < 4) p.r = W / 2
    ctx.fillStyle = hsl(p.r + t * 50, 90, 60)
    ctx.fillRect(W / 2 + cos(p.a) * p.r, H / 2 + sin(p.a) * p.r * 0.7, 2, 2)
  }
}
