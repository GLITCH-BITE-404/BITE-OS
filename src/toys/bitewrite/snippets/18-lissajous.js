// name: lissajous
// about: two sine waves drawing a knot together
// level: easy
function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.05)"
  ctx.fillRect(0, 0, W, H)
  let x = W / 2 + sin(t * 3) * W * 0.4
  let y = H / 2 + sin(t * 2 + PI / 4) * H * 0.4
  ctx.fillStyle = hsl(t * 80, 90, 60)
  ctx.beginPath()
  ctx.arc(x, y, 6, 0, PI * 2)
  ctx.fill()
}
