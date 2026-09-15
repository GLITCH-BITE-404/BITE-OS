// name: plasma
// about: a lava lamp made out of sine waves
// level: medium
let n = 24
function frame(t) {
  let w = W / n, h = H / n
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      let v = sin(i * 0.3 + t) + sin(j * 0.2 - t)
      v += sin((i + j) * 0.2 + t * 1.3)
      ctx.fillStyle = hsl(v * 60 + t * 40, 70, 50)
      ctx.fillRect(i * w, j * h, w + 1, h + 1)
    }
  }
}
