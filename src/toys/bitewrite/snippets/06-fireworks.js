// name: fireworks
// about: rockets that burst into falling sparks
// level: medium
let sparks = []
function boom() {
  let x = rand() * W, y = rand() * H / 2, c = rand() * 360
  for (let i = 0; i < 80; i++) {
    let a = rand() * PI * 2, v = rand() * 5
    sparks.push({ x, y, vx: cos(a) * v, vy: sin(a) * v, c, life: 1 })
  }
}
function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.2)"
  ctx.fillRect(0, 0, W, H)
  if (rand() < 0.04) boom()
  for (let s of sparks) {
    s.x += s.vx; s.y += s.vy; s.vy += 0.06; s.life -= 0.012
    ctx.fillStyle = hsl(s.c, 90, 60, s.life)
    ctx.fillRect(s.x, s.y, 3, 3)
  }
  sparks = sparks.filter(s => s.life > 0)
}
