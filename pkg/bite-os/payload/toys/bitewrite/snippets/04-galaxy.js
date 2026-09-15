// name: galaxy
// about: a spinning spiral of coloured dots
// level: easy
function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.15)"
  ctx.fillRect(0, 0, W, H)
  for (let i = 0; i < 400; i++) {
    let a = i * 0.13 + t
    let r = i * 0.9
    let x = W / 2 + cos(a) * r
    let y = H / 2 + sin(a) * r * 0.6
    ctx.fillStyle = hsl(i + t * 60, 80, 60)
    ctx.fillRect(x, y, 3, 3)
  }
}
