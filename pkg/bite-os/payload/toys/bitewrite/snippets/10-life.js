// name: life
// about: Conway's game of life — cells that breed and die
// level: hard
let s = 16, cw = floor(W / s), ch = floor(H / s), g = []
for (let i = 0; i < cw * ch; i++) g.push(rand() < 0.3 ? 1 : 0)
function at(x, y) {
  return g[((y + ch) % ch) * cw + (x + cw) % cw]
}
function frame(t) {
  let next = []
  ctx.fillStyle = "black"
  ctx.fillRect(0, 0, W, H)
  ctx.fillStyle = ACCENT
  for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
    let k = at(x - 1, y - 1) + at(x, y - 1) + at(x + 1, y - 1)
    k += at(x - 1, y) + at(x + 1, y)
    k += at(x - 1, y + 1) + at(x, y + 1) + at(x + 1, y + 1)
    let alive = k == 3 || (k == 2 && at(x, y))
    next.push(alive ? 1 : 0)
    if (alive) ctx.fillRect(x * s, y * s, s - 1, s - 1)
  }
  g = next
}
