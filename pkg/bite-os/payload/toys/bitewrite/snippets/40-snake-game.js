// name: snake
// about: a game — arrow keys or WASD to steer, eat the dots, don't bite yourself
// level: game
let size = 24, cols = floor(W / size), rows = floor(H / size)
let snake, dir, next, food, score, dead, last

function place() {
  food = { x: floor(rand() * cols), y: floor(rand() * rows) }
}

function reset() {
  snake = [{ x: 5, y: 5 }, { x: 4, y: 5 }, { x: 3, y: 5 }]
  dir = { x: 1, y: 0 }
  next = dir
  score = 0
  dead = false
  last = 0
  place()
}
reset()

function onKey(k) {
  let turns = { up: [0, -1], w: [0, -1], down: [0, 1], s: [0, 1],
                left: [-1, 0], a: [-1, 0], right: [1, 0], d: [1, 0] }
  let t = turns[k]
  if (t && !(t[0] === -dir.x && t[1] === -dir.y)) next = { x: t[0], y: t[1] }
  if (k === "space" && dead) reset()
}

function frame(t) {
  if (!dead && t - last > max(0.05, 0.12 - score * 0.003)) {
    last = t
    dir = next
    let head = { x: (snake[0].x + dir.x + cols) % cols, y: (snake[0].y + dir.y + rows) % rows }
    if (snake.some(p => p.x === head.x && p.y === head.y)) dead = true
    else {
      snake.unshift(head)
      if (head.x === food.x && head.y === food.y) { score++; place() }
      else snake.pop()
    }
  }
  ctx.fillStyle = "black"
  ctx.fillRect(0, 0, W, H)
  ctx.fillStyle = "#ff5577"
  ctx.fillRect(food.x * size + 4, food.y * size + 4, size - 8, size - 8)
  snake.forEach((p, i) => {
    ctx.fillStyle = hsl(120 + i * 6, 80, dead ? 30 : 55)
    ctx.fillRect(p.x * size + 1, p.y * size + 1, size - 2, size - 2)
  })
  ctx.fillStyle = "white"
  ctx.font = "bold 28px monospace"
  ctx.fillText("score " + score, 20, 40)
  if (dead) ctx.fillText("game over — space to play again", W / 2 - 270, H / 2)
}
