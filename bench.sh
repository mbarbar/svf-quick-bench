#!/bin/sh

# GNU time command/path.
time_cmd="/usr/bin/time"
# GNU coreutils timeout command/path.
timeout_cmd="timeout"

usage_exit() {
  echo "usage: $0 SVF_BIN ARGS1 ARGS2 TIME_LIMIT MEM_LIMIT BITCODE..." 1>&2
  echo "     : TIME_LIMIT is in hours" 1>&2
  echo "     : MEM_LIMIT is in GB" 1>&2
  exit 1
}

[ $# -ge 6 ] || usage_exit

wpa="$1"
args1="$2"
args2="$3"
time_limit="$4"
mem_limit="$5"
shift 5
files="$@"
nfiles=`expr $#`

# Check args.
[ -r "$wpa" ] || usage_exit
expr "$time_limit" : "[0-9][0-9]*" > /dev/null || usage_exit
expr "$mem_limit" : "[0-9][0-9]*" > /dev/null || usage_exit
# 9 is the length of "Geo. Mean".
longest_filename=9
for f in $files; do
  [ -r "$f" ] || usage_exit;
  if [ "${#f}" -gt "$longest_filename" ]; then
    longest_filename=${#f}
  fi
done

echo "  = args = "
echo "    svf binary    : $wpa"
echo "    args1         : $args1"
echo "    args2         : $args2"
echo "    time limit    : $time_limit hours"
echo "    memory limit  : $mem_limit gigabytes"
echo "    bitcode files : $files ($nfiles)"

time_limit_s=$(($time_limit * 60 * 60))
mem_limit_b=$(($mem_limit * 1000 * 1000 * 1000))
time_fmt="real %e\nrss %M"

time_txt=`mktemp`
echo > log.txt

printf "┌─%s─┬───────────────────────┬───────────────────────┬───────────────────────────┐\n"\
  $(head -c $longest_filename < /dev/zero | sed -e 's/\x0/─/g')
printf "│ %${longest_filename}s │         ARGS 1        │         ARGS 2        │      Difference (1/2)     │\n" ""
printf "│ %${longest_filename}s ├┄┄┄┄┄┄┄┄┄┄┄┄┬┄┄┄┄┄┄┄┄┄┄┼┄┄┄┄┄┄┄┄┄┄┄┄┬┄┄┄┄┄┄┄┄┄┄┼┄┄┄┄┄┄┄┄┄┄┄┄┄┬┄┄┄┄┄┄┄┄┄┄┄┄┄┤\n" "Program"
printf "│ %${longest_filename}s │ %10s │ %8s │ %10s │ %8s │ %11s │ %11s │\n"\
  " " "Time" "Memory" "Time" "Memory" "Time" "Memory"
printf "├─%s─┼────────[s]─┼─────[GB]─┼────────[s]─┼─────[GB]─┼─────────────┼─────────────┤\n"\
  $(head -c $longest_filename < /dev/zero | sed -e 's/\x0/─/g')

mem_diff_product_cmd="1"
time_diff_product_cmd="1"

# Whether the mean time/mem. diff. needs to have a sign in front of it.
mean_time_diff_gt=""
mean_time_diff_lt=""
mean_mem_diff_gt=""
mean_mem_diff_lt=""

for f in $files; do
  cmd="$wpa $args1 $f"
  oox1=""
  oox2=""

  echo "  = running $cmd" >> log.txt
  if $timeout_cmd --foreground $time_limit_s \
       $time_cmd -f "$time_fmt" -o "$time_txt" \
       prlimit --as=$mem_limit_b: \
       $cmd $f >> log.txt 2>&1; then
    echo "    = success" >> log.txt
    time1=`grep real $time_txt | cut -f2 -d\ `
    disp_time1=$(printf "%10.2f" "$time1")
    mem1=`grep rss $time_txt | cut -f2 -d\ `
    disp_mem1=$(printf "%8.2f" $(echo "$mem1 / 1000 / 1000" | bc -l))
  else
    if [ $? -eq 124 ]; then
      echo "    = OOT" >> log.txt
      oox1="OOT"
      time1=$time_limit_s
      disp_time1="OOT"
      disp_mem1="--"
    else
      echo "    = OOM" >> log.txt
      oox1="OOM"
      mem1=$(($mem_limit_b / 1000))
      disp_time1="--"
      disp_mem1="OOM"
    fi
  fi

  # Repeat twice, easier than a loop.
  cmd="$wpa $args2 $f"
  echo "  = running $cmd" >> log.txt
  if $timeout_cmd --foreground $time_limit_s \
       $time_cmd -f "$time_fmt" -o "$time_txt" \
       prlimit --as=$mem_limit_b: \
       $cmd $f >> log.txt 2>&1; then
    echo "    = success" >> log.txt
    time2=`grep real $time_txt | cut -f2 -d\ `
    disp_time2=$(printf "%8.2f" "$time2")
    mem2=`grep rss $time_txt | cut -f2 -d\ `
    disp_mem2=$(printf "%8.2f" $(echo "$mem2 / 1000 / 1000" | bc -l))
  else
    if [ $? -eq 124 ]; then
      echo "    = OOT" >> log.txt
      oox2="OOT"
      time2=$time_limit_s
      disp_time2="OOT"
      disp_mem2="--"
    else
      echo "    = OOM" >> log.txt
      oox2="OOM"
      mem2=$(($mem_limit_b / 1000))
      disp_time2="--"
      disp_mem2="OOM"
    fi
  fi

  # Recall, when OOM, we set mem to be the memory limit. Similarly for OOT/time.
  # When OOM or OOT, we can calculate time or memory, respectively.
  if [ "$oox1" != "OOM" -a "$oox2" != "OOM" ]; then
    time_diff=$(printf "%.2f" $(echo $time1 / $time2 | bc -l))
  fi

  if [ "$oox1" != "OOT" -a "$oox2" != "OOT" ]; then
    mem_diff=$(printf "%.2f" $(echo $mem1 / $mem2 | bc -l))
  fi

  # Whether we have a value or not depends on whether we went OOM/OOT.
  if [ -n "$oox1" -a -n "$oox2" ]; then
    time_diff="--"
    mem_diff="--"
  elif [ "$oox1" = "OOT" ]; then
    time_diff_product_cmd="$time_diff_product_cmd * $time_diff"
    time_diff=$(printf "%9s" ">=$time_diff")
    time_diff_gt=">="
    mem_diff="--"
  elif [ "$oox2" = "OOT" ]; then
    time_diff_product_cmd="$time_diff_product_cmd * $time_diff"
    time_diff=$(printf "%9s" "<=$time_diff")
    time_diff_lt="<="
    mem_diff="--"
  elif [ "$oox1" = "OOM" ]; then
    time_diff="--"
    mem_diff_product_cmd="$mem_diff_product_cmd * $mem_diff"
    mem_diff=$(printf "%9s" ">=$mem_diff")
    mem_diff_gt=">="
  elif [ "$oox2" = "OOM" ]; then
    time_diff="--"
    mem_diff_product_cmd="$mem_diff_product_cmd * $mem_diff"
    mem_diff=$(printf "%9s" "<=$mem_diff")
    mem_diff_lt="<="
  else
    time_diff_product_cmd="$time_diff_product_cmd * $time_diff"
    time_diff=$(printf "%9s" "$time_diff")
    mem_diff_product_cmd="$mem_diff_product_cmd * $mem_diff"
    mem_diff=$(printf "%9s" "$mem_diff")
  fi

  printf "│ %${longest_filename}s │ %10s │ %8s │ %10s │ %8s │ %10sx │ %10sx │\n"\
    "$f" "$disp_time1" "$disp_mem1" "$disp_time2" "$disp_mem2" "$time_diff" "$mem_diff"
done

# We might have gotten <==> so we need to sed it out.
time_diff_sign=$(echo "${time_diff_lt}${time_diff_gt}" | sed -e 's/==/=/')
mem_diff_sign=$(echo "${mem_diff_lt}${mem_diff_gt}" | sed -e 's/==/=/')

# Count the number of asteriks (multiplication) in the diff command. 0 means we have no diffs, 1 means
# we have 1 diff and so the mean is just that, and for any more we perform the standard mean calculation.
mult_in_time_diff=$(echo "$time_diff_product_cmd" | tr -cd '*' | wc -c)
mult_in_mem_diff=$(echo "$mem_diff_product_cmd" | tr -cd '*' | wc -c)

if [ "$mult_in_time_diff" -gt 1 ]; then
  disp_time_diff_geomean=$(printf "${time_diff_sign}%.2f" $(echo "sqrt($time_diff_product_cmd)" | bc -l))
elif [ "$mult_in_time_diff" -eq 1 ]; then
  disp_time_diff_geomean=$(printf "${time_diff_sign}%.2f" $(echo "$time_diff_product_cmd" | bc -l))
else
  disp_time_diff_geomean="--"
fi

if [ "$mult_in_mem_diff" -gt 1 ]; then
  disp_mem_diff_geomean=$(printf "${mem_diff_sign}%.2f" $(echo "sqrt($mem_diff_product_cmd)" | bc -l))
elif [ "$mult_in_mem_diff" -eq 1 ]; then
  disp_mem_diff_geomean=$(printf "${mem_diff_sign}%.2f" $(echo "$mem_diff_product_cmd" | bc -l))
else
  disp_mem_diff_geomean="--"
fi

printf "├─%s─┼───────────────────────────────────────────────┼─────────────┼─────────────┤\n"\
  $(head -c $longest_filename < /dev/zero | sed -e 's/\x0/─/g')
printf "│ %${longest_filename}s │                                               │ %10sx │ %10sx │\n"\
  "Geo. Mean" "$disp_time_diff_geomean" "$disp_mem_diff_geomean" 
printf "└─%s─┴───────────────────────────────────────────────┴───────────────────────────┘\n"\
  $(head -c $longest_filename < /dev/zero | sed -e 's/\x0/─/g')
