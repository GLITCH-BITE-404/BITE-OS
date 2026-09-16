# name: rainbow scroll
# about: a line of text sliding through every colour
# level: easy
text="i will stick with you   "
read -r h w < <(stty size)
printf '\033[2J\033[?25l'
trap 'printf "\033[0m\033[?25h"' EXIT

for f in $(seq 0 400); do
  printf '\033[H'
  for (( row = 0; row < h - 1; row++ )); do
    s=$(( (f + row) % ${#text} ))
    line="${text:s}${text:0:s}"
    while (( ${#line} < w )); do line+="$line"; done
    printf '\033[38;5;%dm%s\n' $(( (f + row) % 216 + 16 )) "${line:0:w}"
  done
  sleep 0.05
done
