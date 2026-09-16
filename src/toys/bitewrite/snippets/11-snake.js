// name: rainbow snake
// about: a glowing chain chasing its own head around the screen
// level: medium
let num = 12, x = Array(num).fill(100), y = Array(num).fill(100)
let vx = 4, vy = 4, c = 0

function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.08)"
  ctx.fillRect(0, 0, W, H)

  x[0] += vx
  y[0] += vy
  c += 0.5

  if (x[0] < 20) { x[0] = 20; vx = -vx }
  if (x[0] > W - 20) { x[0] = W - 20; vx = -vx }
  if (y[0] < 20) { y[0] = 20; vy = -vy }
  if (y[0] > H - 20) { y[0] = H - 20; vy = -vy }

  if (Math.random() > 0.98) {
    let angle = (Math.random() - 0.5) * 0.5
    let cos = Math.cos(angle), sin = Math.sin(angle)
    let nx = vx * cos - vy * sin
    vy = vx * sin + vy * cos
    vx = nx
  }

  for (let i = 1; i < num; i++) {
    x[i] += (x[i - 1] - x[i]) * 0.3
    y[i] += (y[i - 1] - y[i]) * 0.3
  }

  for (let i = num - 1; i >= 0; i--) {
    let r = 6 + (num - i) * 1.5

    ctx.fillStyle = `hsl(${(c + i * 8) % 360}, 85%, 55%)`
    ctx.beginPath()
    ctx.arc(x[i], y[i], r, 0, Math.PI * 2)
    ctx.fill()
  }
}
