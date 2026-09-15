// name: wavy
// about: your words riding a rainbow sine wave
// level: easy
let msg = "i will stick with you "
function frame(t) {
  ctx.fillStyle = "black"
  ctx.fillRect(0, 0, W, H)
  ctx.font = "bold 40px monospace"
  for (let i = 0; i < msg.length; i++) {
    let y = H / 2 + sin(t * 3 + i * 0.4) * 60
    ctx.fillStyle = hsl(i * 16 + t * 90, 90, 65)
    ctx.fillText(msg[i], 40 + i * 30, y)
  }
}
