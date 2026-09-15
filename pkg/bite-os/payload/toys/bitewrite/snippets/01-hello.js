// name: hello
// about: the smallest one — a dot riding a circle
// level: easy
function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.2)"
  ctx.fillRect(0, 0, W, H)
  let x = W / 2 + cos(t * 2) * 200
  let y = H / 2 + sin(t * 2) * 200
  ctx.fillStyle = ACCENT
  ctx.beginPath()
  ctx.arc(x, y, 30, 0, PI * 2)
  ctx.fill()
}
