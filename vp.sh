#!/bin/bash
# this is a file that logs directorys to protect against
# show if they have been temperd by third partys.

logs_file="/tmp/.pdb"
pathern_to_ignore=""
is_output_to_log=false
mode="viguia"

#todo shows help
print_help(){
  cat << EOF
Uso: ./vp  [-f <ficheiro>] [-e <ignore_pattern>] [-s]\
 [{-p <dir1[<dir2>...] | -c}]
-p : Protege e guarda informação acerca de um ou mais diretórios
-v : Verifica alterações em ficheiros desde que foram protegidos\
 sendo este modo escolido por defeito.
-f : Indicação do nome do ficheiro onde a base de dados será guardada\
 (Por defeito será tmp/.pdb)
-e : Permite a exclusão de ficheiros voláteis (ex. *.tmp, *.log,
/tmp/*) da proteção e verificação
-s : Emissão de alertas de alta prioridade para o sistema de logging
usando o logger
EOF

}

#todo
# valida o resto dos argumentos que não são otps
# casos seja modo vigia tem de estar vazio
# caso seja modo de proteção contem os ficheiros que
# são para proteger.
assert_valid_remaing_files(){
  if [[ $mode = "viguia" ]]; then
    if [[ $# -ne 0 ]]; then
      echo "erro: modo vigia não pode ter ficheiros para \
      guardar" >&2
      exit 1
    fi
  else
    if [[ $# -eq 0 ]];then
      echo "must be at least 1 file to protect">&2
      exit 1
    fi
    for argument in "$@"; do
      if ! [[ -d "$argument" ]]; then
        echo "there is no directory $argument">&2
        exit 1
      fi
      if ! [[ -r "$argument" ]] || ! [[ -e "$argument" ]]; then
        echo "error directory $argument must be readable \
        and executable">&2
        exit 1
      fi
    done
  fi
  return 0
}

# $1 logs file to assert
assert_logs_file(){
  local unverified_logs_file=$1

  if ! [[ -z $1 ]]; then
    logs_file=$unverified_logs_file
  fi

  if [[ $mode = "viguia" ]]; then
    if ! [[ -f $logs_file ]]; then
      echo "in mode viguia there must be a existing \
      logs file, but the file '$logs_file' does not exist ">&2
      exit 1
    fi
    if ! [[ -r $logs_file ]]; then
      echo "the logs file must have reading permitions">&2
      exit 1
    fi
  else
    if [[ -e $logs_file ]]; then
      echo "In protection mode the file you are writing to must \
      not exist">&2
      exit 1
    fi
    touch "$logs_file"
    if [[ "$?" -ne 0 ]]; then
      echo "there was an error while creating the logs file">&2
      exit 1
    fi
    chmod 644 "$logs_file"
  fi

  #se estiver no modo guarda o ficheiro não pode existir:
  #se estiver no modo de vigia o ficheiro tem de existir 
  # com permições de leitura
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
  assert_logs_file "$unverified_logs_file"
  assert_valid_remaing_files "$@"
  if [[ $mode = viguia ]]; then
    view_mode
  else
    protect_mode "$@"
  fi
}

protect_mode(){
  touch "$logs_file"
  chmod 644 "$logs_file"

  save_header
  for folder in "$@"; do
    protect_folder "$folder"
    if [[ $is_output_to_log = true ]];then
      logger --priority info "$folder was saved"
    fi 
  done
  if [[ $is_output_to_log = true ]];then
    logger --priority info ""
  fi 
}


# $1 -> directory to protect 
protect_folder(){
  for element in "$1"/*; do
    if [[ -d $element ]]; then
      protect_folder "$element"
    else
      save_file_metadata "$element"
    fi
  done
  save_file_metadata "$1"
}

save_header(){
  echo "user_id,group_id,size,permitions,modification_date,\
  file_type,sha256,file_path" > "$logs_file"
}

# $1 file to save the metadata
save_file_metadata(){
  local file="$1"
  if [[ "$file" =~ ^$pathern_to_ignore$ ]]; then
    return 0
  fi
  if ! [[ -d $file ]]; then
    sha256=$(sha256sum "$file" | awk '{print $1}')
  else
    sha256="n\a"
  fi
  truepath=$(realpath "$file")
  #falta validar se o ficheiro tem ',' no meio pode dar erro
  stat --format="%u,%g,%s,%a,%y,%F,$sha256,$truepath" "$file" >> "$logs_file"
}

view_mode(){    
  n_correct_files=0
  n_ignored_files=0
  n_deleted_files=0
  n_added_files=0
  n_changued_files=0
  while read -r line  ; do
    validate_arguments "$line"
  done <<< "$(tail -n +2 "$logs_file")"
  echo "final report:"
  echo "number files read corretly $n_correct_files"
  echo "number files deleted $n_deleted_files"
  echo "number added files $n_added_files"
  echo "number changued files $n_changued_files"
  echo "number ignored files $n_ignored_files"
  if [[ $is_output_to_log = true ]] && ( [[ $n_added_files -ne 0 ]]\
   || [[ $n_deleted_files -ne 0 ]] || [[ $n_changued_files -ne 0 ]]); then
    logger --priority alert "Alert protect directories where compromised."
  fi
  return 0
}

validate_arguments(){
  line="$1"
  stored_file_truepath="$(echo "$line" | awk -F"," '{print $8}')"
  if [[ $stored_file_truepath =~ ^$pathern_to_ignore$ ]]; then
    ((n_ignored_files++))
    return 0
  fi
  stored_user_id="$(echo "$line" | awk -F"," '{print $1}')"
  stored_goup_id="$(echo "$line" | awk -F"," '{print $2}')"
  stored_size="$(echo "$line" | awk -F"," '{print $3}')"
  stored_permitions="$(echo "$line" | awk -F"," '{print $4}')"
  stored_mod_date="$(echo "$line" | awk -F"," '{print $5}')"
  stored_file_type="$(echo "$line" | awk -F"," '{print $6}')"
  stored_sha256="$(echo "$line" | awk -F"," '{print $7}')"
  real_user_id="$(stat --format="%u" "$stored_file_truepath")"
  real_group_id="$(stat --format="%g" "$stored_file_truepath")"
  real_size="$(stat --format="%s" "$stored_file_truepath")"
  real_permitions="$(stat --format="%a" "$stored_file_truepath")"
  real_mod_date="$(stat --format="%y" "$stored_file_truepath")"
  real_file_type="$(stat --format="%F" "$stored_file_truepath")"
  if [[ -d $stored_file_truepath ]];then 
    real_sha256="n\a"
  else
    real_sha256="$(sha256sum "$stored_file_truepath" | awk '{print $1}')"
  fi
  current_file_was_modified=false
  new_file_added=false

  if ! [[ -e $stored_file_truepath ]]; then
    echo "the file $stored_file_truepath is currently not in the system"
    ((n_deleted_files++))
    return 0
  fi

  if [[ $stored_user_id -ne $real_user_id ]]; then
    current_file_was_modified="true"
    echo "Warning the file $stored_file_truepath was changued:\
    stored with user id $stored_user_id , but with the \
    value: $real_user_id "
  fi

  if [[ $stored_goup_id -ne $real_group_id  ]]; then
    current_file_was_modified="true"
    echo "Warning the file $stored_file_truepath was changued:\
    stored with group id $stored_goup_id , but with the \
    value: $real_group_id "
  fi

  if [[ $stored_size -ne $real_size  ]]; then
    current_file_was_modified="true"
    echo "Warning the file $stored_file_truepath was changued:\
    stored with size $stored_size , but with the \
    value: $real_size "
  fi

  if [[ $stored_permitions -ne $real_permitions  ]]; then
    current_file_was_modified="true"
    echo "Warning the file $stored_file_truepath was changued:\
    stored with permitions $stored_permitions , but with the \
    value: $real_permitions "
  fi

if [[ "$stored_mod_date" != "$real_mod_date"  ]]; then
    current_file_was_modified="true"
    echo "Warning the file $stored_file_truepath was modified:\
    stored with the original mod date $stored_mod_date , but with the \
    value: $real_mod_date "
  fi

  if [[ "$stored_file_type" != "$real_file_type"  ]]; then
    current_file_was_modified="true"
    echo "Warning the file $stored_file_truepath was changued:\
    stored for file type $stored_file_type , but with the \
    value: $real_file_type"
  fi

  if [[ "$real_sha256" != "$stored_sha256"  ]]; then
    current_file_was_modified="true"
    echo "Warning the file $stored_file_truepath was changued:\
    stored shasum $stored_sha256 , but with the actual \
    value is: $real_sha256 "
  fi
  if [[ -d "$stored_file_truepath" ]];then 
    verify_new_files_in_directory "$stored_file_truepath"
    if [[ $? -ne 0 ]]; then
      new_file_added=true
    fi
  fi
  if [[ $current_file_was_modified = false ]] && [[ $new_file_added = false ]]; then
    ((n_correct_files++))
  elif [[ $current_file_was_modified != false ]]; then
    ((n_changued_files++))
  fi
}

# $1 dir 
verify_new_files_in_directory(){
  dir=$1
  is_file_added=0
  for file in "$dir"/*; do
    real_of_path_file="$(realpath "$file")"
    grep -q "$real_of_path_file" "$logs_file"
    if [[ $? -eq 0 ]];then 
      continue
    fi
    is_file_added=1
    if ! [[ -d $file ]]; then
    ((n_added_files++))
    echo file was added
      continue
    fi

    find "$file" | while read -rd $'\0' sub_file; do
      ((n_added_files++))
      echo "$sub_file was created"
    done
  done
  return $is_file_added
  }

parseArgs "$@"