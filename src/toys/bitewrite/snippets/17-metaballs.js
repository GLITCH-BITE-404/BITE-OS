// name: metaballs
// about: blobs that melt into each other, worked out cell by cell
// level: extreme
let cols = 90, rows = 56, balls = []
for (let i = 0; i < 6; i++)
  balls.push({ x: rand() * cols, y: rand() * rows, vx: rand() - 0.5, vy: rand() - 0.5 })

function frame(t) {
  let w = W / cols, h = H / rows
  for (let b of balls) {
    b.x += b.vx; b.y += b.vy
    if (b.x < 0 || b.x > cols) b.vx = -b.vx
    if (b.y < 0 || b.y > rows) b.vy = -b.vy
  }
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) {
      let v = 0
      for (let b of balls) v += 40 / ((i - b.x) ** 2 + (j - b.y) ** 2 + 1)
      ctx.fillStyle = v > 1 ? hsl(v * 40 + t * 30, 90, 55) : "black"
      ctx.fillRect(i * w, j * h, w + 1, h + 1)
    }
  }
}
