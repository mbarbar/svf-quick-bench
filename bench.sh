#!/bin/sh

time_cmd="/usr/bin/time"
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
# 7 is the length of "Program".
longest_filename=7
for f in $files; do
  [ -r "$f" ] || usage_exit;
  if [ "${#f}" -gt "$longest_filename" ]; then
    longest_filename=${#f}
  fi
done

echo " ===== Clustering Benchmark ===== "
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

printf "┌─%s─┬───────────────────────┬───────────────────────┬─────────────────────┐\n"\
  `head -c $longest_filename < /dev/zero | tr '\0' '─'`
printf "│ %${longest_filename}s │         ARGS 1        │         ARGS 2        │   Difference (1/2)  │\n" ""
printf "│ %${longest_filename}s ├┄┄┄┄┄┄┄┄┄┄┄┄┬┄┄┄┄┄┄┄┄┄┄┼┄┄┄┄┄┄┄┄┄┄┄┄┬┄┄┄┄┄┄┄┄┄┄┼┄┄┄┄┄┄┄┄┄┄┬┄┄┄┄┄┄┄┄┄┄┤\n" "Program"
printf "│ %${longest_filename}s │ %10s │ %8s │ %10s │ %8s │ %8s │ %8s │"\
  " " "Time" "Memory" "Time" "Memory" "Time" "Memory"

for f in $files; do
  cmd="$wpa $args1 $f"
  echo "  = running $cmd"
  echo "@@@@@@@@\n$cmd\n" >> log.txt
  if $timeout_cmd $time_limit_s \
       $time_cmd -f "$time_fmt" -o "$time_txt" \
       prlimit --as=$mem_limit_b: \
       $cmd $f >> log.txt; then
    echo "    = success"
    time1=`grep real $time_txt | cut -f2 -d\ `
    disp_time1="$time1"
    mem1=`grep real $time_txt | cut -f2 -d\ `
    disp_mem1="$time1"
  else
    if [ $? -eq 124 ]; then
      echo "    = OOT"
      oox1="OOT"
      time1=$time_limit_s
      disp_time2="OOT"
      disp_mem2="--"
    else
      echo "    = OOM"
      oox1="OOM"
      mem1=$mem_limit_b
      disp_time2="--"
      disp_mem2="OOM"
    fi
  fi

  cmd="$wpa $args2 $f"
  echo "  = running $cmd"
  echo "@@@@@@@@\n$cmd\n" >> log.txt
  if $timeout_cmd $time_limit_s \
       $time_cmd -f "$time_fmt" -o "$time_txt" \
       prlimit --as=$mem_limit_b: \
       $cmd $f >> log.txt; then
    echo "    = success"
    time2=`grep real $time_txt | cut -f2 -d\ `
    disp_time2="$time2"
    mem2=`grep real $time_txt | cut -f2 -d\ `
    disp_mem2="$mem2"
  else
    if [ $? -eq 124 ]; then
      echo "    = OOT"
      oox2="OOT"
      time2=$time_limit_s
      disp_time2="OOT"
      disp_mem2="--"
    else
      echo "    = OOM"
      oox2="OOM"
      mem2=$mem_limit_b
      disp_time2="--"
      disp_mem2="OOM"
    fi
  fi

  printf "│ %$longest_filename │ %10.2f │ %8.2f │ %10.2f │ %8.2f │ %8.2f │ %8.2f │"\
    "$f" "$disp_time1" "$disp_mem1" "$disp_time2" "$disp_mem2" $(($time1/$time2)) $(($mem1/$mem2))
done

