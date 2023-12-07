run:
  perl amulet.pl

test:
  @printf "%b" "DON'T WORRY." | ./amulet.pl
  @printf "%b" "If you can't write poems,\nwrite me" | ./amulet.pl
