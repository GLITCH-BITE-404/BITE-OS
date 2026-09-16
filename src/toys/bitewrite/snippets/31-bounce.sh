# name: bouncing ball
# about: a ball bouncing around your terminal, changing colour on every wall
# level: easy
read -r h w < <(stty size)
x=5; y=5; dx=1; dy=1; c=31
printf '\033[2J\033[?25l'
trap 'printf "\033[0m\033[?25h"' EXIT

for f in $(seq 1 600); do
  printf '\033[%d;%dH ' "$y" "$x"
  x=$((x + dx)); y=$((y + dy))
  if (( x <= 1 || x >= w )); then dx=$((-dx)); c=$((c % 6 + 31)); fi
  if (( y <= 1 || y >= h )); then dy=$((-dy)); c=$((c % 6 + 31)); fi
  printf '\033[%d;%dH\033[1;%dm●' "$y" "$x" "$c"
  sleep 0.02
done
