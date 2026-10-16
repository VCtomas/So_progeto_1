#!/bin/bash
# this is a file that logs directorys to protect against
# show if they have been temperd by third partys.

logs_file="/tmp/.pdb"
pathern_to_ignore=""
is_output_to_log=false
mode="viguia"

#todo shows help
print_help(){
  echo foo
}

#todo
# valida o resto dos argumentos que não são otps
# casos seja modo vigia tem de estar vazio
# caso seja modo de proteção contem os ficheiros que
# são para proteger.
assert_correct_files(){
  echo foo
}

# todo validates the log file
assert_valid_file(){
  echo foo
}

#######################################
# Parse the arguments given in the terminal
# Globals:
#   logs_file
# Arguments:
#   arguments given to the scritp with $@
#######################################
parseArgs(){
  local unverified_logs_file
  local number_opt_p_v_called=0
  
  while getopts ":hpvf:e:s" opt; do
    case "$opt" in
      h)  print_help ; exit 0;;
      p)  mode="protecao"; ((number_opt_p_v_called++));;
      v)  mode="viguia"; ((number_opt_p_v_called++));;
      f)  unverified_logs_file="$OPTARG";;
      e)  pathern_to_ignore="$OPTARG";;
      s)  is_output_to_log="true";;
      \?) echo "invalid option $opt">&2; print_help ;exit 1;;
    esac
  done
  shift $((OPTIND - 1))
  if [[ number_opt_p_v_called -gt 1 ]];then
    echo "you can not call -v and -p at the same time">&2
    exit 1
  fi
  assert_valid_file "$unverified_logs_file"
  assert_valid_remaing_files "$@"
}

parseArgs "$@"