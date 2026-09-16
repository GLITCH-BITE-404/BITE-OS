// name: spinning cube
// about: a 3D wireframe cube, rotated and projected by hand
// level: hard
let pts = []
for (let i = 0; i < 8; i++)
  pts.push([i & 1 ? 1 : -1, i & 2 ? 1 : -1, i & 4 ? 1 : -1])
let edges = []
for (let a = 0; a < 8; a++)
  for (let b = a + 1; b < 8; b++)
    if ([1, 2, 4].includes(a ^ b)) edges.push([a, b])

function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.25)"
  ctx.fillRect(0, 0, W, H)
  let p = pts.map(([x, y, z]) => {
    let x1 = x * cos(t) - z * sin(t), z1 = x * sin(t) + z * cos(t)
    let y1 = y * cos(t * 0.7) - z1 * sin(t * 0.7)
    let z2 = y * sin(t * 0.7) + z1 * cos(t * 0.7)
    let s = min(W, H) * 0.9 / (z2 + 4)
    return [W / 2 + x1 * s, H / 2 + y1 * s]
  })
  ctx.lineWidth = 3
  edges.forEach(([a, b], i) => {
    ctx.strokeStyle = hsl(t * 60 + i * 30, 90, 60)
    ctx.beginPath()
    ctx.moveTo(p[a][0], p[a][1])
    ctx.lineTo(p[b][0], p[b][1])
    ctx.stroke()
  })
}
