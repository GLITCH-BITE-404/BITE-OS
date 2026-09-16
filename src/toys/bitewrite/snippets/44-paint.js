// name: paint
// about: hold the mouse to paint in rainbow — press c to clear
// level: game
let lx = -1, ly = -1, hue = 0

function onKey(k) {
  if (k === "c") {
    ctx.fillStyle = "black"
    ctx.fillRect(0, 0, W, H)
  }
}

function frame(t) {
  if (!mouse.down) { lx = -1; return }
  hue += 3
  ctx.strokeStyle = hsl(hue, 90, 60)
  ctx.lineWidth = 12
  ctx.lineCap = "round"
  ctx.beginPath()
  ctx.moveTo(lx < 0 ? mouse.x : lx, lx < 0 ? mouse.y : ly)
  ctx.lineTo(mouse.x, mouse.y)
  ctx.stroke()
  lx = mouse.x
  ly = mouse.y
}
