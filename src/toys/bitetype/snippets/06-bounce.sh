#! name: bouncing ball
#! lang: bash
#! knob SPEED 1 20 1
#! knob COLOR 31 96 1
SPEED=6; COLOR=95
read -r h w < <(stty size)
x=5; y=5; dx=1; dy=1
for f in $(seq 1 120); do
  printf '\033[2J\033[%d;%dH\033[%dm@' "$y" "$x" "$COLOR"
  x=$((x+dx)); y=$((y+dy))
  (( x<=1 || x>=w )) && dx=$((-dx)); (( y<=1 || y>=h )) && dy=$((-dy))
  sleep 0.$(printf '%02d' $SPEED)
done
