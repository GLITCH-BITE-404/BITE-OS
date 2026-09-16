# name: big clock
# about: the time in huge block digits, redrawn every second
# level: medium
font=("#### ## ## ####" " # ##  #  # ###" "###  #####  ###" "###  ####  ####" "# ## ####  #  #"
      "####  ###  ####" "####  #### ####" "###  #  #  #  #" "#### ##### ####" "#### ####  ####")
printf '\033[2J\033[?25l'
trap 'printf "\033[0m\033[?25h"' EXIT

for i in $(seq 1 120); do
  now=$(date +%H:%M:%S)
  read -r h w < <(stty size)
  top=$(( h / 2 - 5 )); left=$(( w / 2 - 30 ))
  for (( r = 0; r < 5; r++ )); do
    line=""
    for (( k = 0; k < ${#now}; k++ )); do
      ch=${now:k:1}
      if [[ $ch == ":" ]]; then
        if (( r == 1 || r == 3 )); then line+="  ██  "; else line+="      "; fi
      else
        g=${font[ch]:r*3:3}
        g=${g//#/██}; g=${g// /  }
        line+="$g  "
      fi
    done
    printf '\033[%d;%dH\033[1;%dm%s' $(( top + r * 2 )) "$left" $(( 31 + i % 6 )) "$line"
    printf '\033[%d;%dH%s' $(( top + r * 2 + 1 )) "$left" "$line"
  done
  sleep 1
done
