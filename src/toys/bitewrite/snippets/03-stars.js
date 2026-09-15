// name: starfield
// about: fly through space at warp speed
// level: easy
let stars = []
for (let i = 0; i < 300; i++)
  stars.push({ x: rand() * 2 - 1, y: rand() * 2 - 1, z: rand() })
function frame(t) {
  ctx.fillStyle = "black"
  ctx.fillRect(0, 0, W, H)
  ctx.fillStyle = TEXT
  for (let s of stars) {
    s.z -= 0.008
    if (s.z <= 0) s.z = 1
    let x = W / 2 + s.x / s.z * W / 3
    let y = H / 2 + s.y / s.z * H / 3
    let r = (1 - s.z) * 4
    ctx.fillRect(x, y, r, r)
  }
}
