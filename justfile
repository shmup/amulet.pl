run:
  perl amulet.pl

test:
  @./amulet.pl "DON'T WORRY."
  @printf "%b" "If you can't write poems,\nwrite me" | ./amulet.pl
