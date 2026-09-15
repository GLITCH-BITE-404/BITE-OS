// name: tunnel
// about: fall down a neon tunnel forever
// level: medium
function frame(t) {
  ctx.fillStyle = "rgba(0, 0, 0, 0.3)"
  ctx.fillRect(0, 0, W, H)
  ctx.lineWidth = 2
  for (let i = 0; i < 20; i++) {
    let z = (i - t * 4) % 20
    if (z < 0) z += 20
    let r = 2000 / (z + 1)
    let x = W / 2 + sin(t + z * 0.3) * 40
    ctx.strokeStyle = hsl(z * 18 + t * 50, 90, 60)
    ctx.strokeRect(x - r, H / 2 - r * 0.6, r * 2, r * 1.2)
  }
}
