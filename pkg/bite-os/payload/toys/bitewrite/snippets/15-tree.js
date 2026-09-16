// name: fractal tree
// about: a tree drawn by a function that calls itself, swaying in the wind
// level: hard
function branch(x, y, len, ang, depth, t) {
  if (depth === 0) return
  let x2 = x + cos(ang) * len, y2 = y + sin(ang) * len
  ctx.strokeStyle = hsl(100 + depth * 20, 70, 30 + depth * 5)
  ctx.lineWidth = depth
  ctx.beginPath()
  ctx.moveTo(x, y)
  ctx.lineTo(x2, y2)
  ctx.stroke()
  let sway = sin(t * 1.5 + depth) * 0.12
  branch(x2, y2, len * 0.72, ang - 0.45 + sway, depth - 1, t)
  branch(x2, y2, len * 0.72, ang + 0.45 + sway, depth - 1, t)
}

function frame(t) {
  ctx.fillStyle = "black"
  ctx.fillRect(0, 0, W, H)
  branch(W / 2, H, H / 4, -PI / 2, 10, t)
}
