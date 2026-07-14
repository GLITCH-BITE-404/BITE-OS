#!/usr/bin/env bash
# Toggle floating. On float, place an 800x600 window centered on the cursor.

hyprctl dispatch togglefloating >/dev/null

floating=$(hyprctl activewindow -j | jq -r .floating)
[ "$floating" != "true" ] && exit 0

read -r cx cy < <(hyprctl cursorpos | tr ',' ' ')

w=800
h=600
x=$(( cx - w/2 ))
y=$(( cy - h/2 ))

hyprctl --batch "dispatch resizeactive exact $w $h ; dispatch moveactive exact $x $y" >/dev/null
