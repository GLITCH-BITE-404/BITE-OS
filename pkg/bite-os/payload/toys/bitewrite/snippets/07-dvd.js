// name: dvd
// about: the bouncing logo — will it ever hit the corner?
// level: medium
let x = 50, y = 50, vx = 3, vy = 2, c = 0, w = 210
function frame(t) {
  ctx.fillStyle = "black"
  ctx.fillRect(0, 0, W, H)
  x += vx; y += vy
  if (x < 0 || x > W - w) { vx = -vx; c += 70 }
  if (y < 0 || y > H - 50) { vy = -vy; c += 70 }
  ctx.fillStyle = hsl(c, 90, 60)
  ctx.font = "bold 44px sans-serif"
  ctx.fillText("BITE-OS", x, y + 44)
}
