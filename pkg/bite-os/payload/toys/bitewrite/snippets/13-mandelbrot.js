// name: mandelbrot dive
// about: zooming into the edge of the Mandelbrot set, forever
// level: extreme
let cols = 80, rows = 50, cx = -0.743643887, cy = 0.131825904

function frame(t) {
  let k = t % 30, span = 3 / pow(1.25, k), top = 40 + floor(k * 2)
  let w = W / cols, h = H / rows
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) {
      let x0 = cx + (i / cols - 0.5) * span * W / H
      let y0 = cy + (j / rows - 0.5) * span
      let x = 0, y = 0, n = 0
      while (x * x + y * y < 4 && n < top) {
        let xt = x * x - y * y + x0
        y = 2 * x * y + y0
        x = xt
        n++
      }
      ctx.fillStyle = n === top ? "black" : hsl(n * 9 + t * 40, 90, 55)
      ctx.fillRect(i * w, j * h, w + 1, h + 1)
    }
  }
}
