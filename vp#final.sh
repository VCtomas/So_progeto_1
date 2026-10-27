#!/bin/bash
# this is a file that logs directorys to protect against
# show if they have been temperd by third partys.

logs_file="/tmp/.pdb"
pathern_to_ignore=""
is_output_to_log=false
mode="viguia"

# Mostra a ajuda e a forma correta de utilizar os comandos.
print_help(){
  cat << EOF
Uso: ./vp  [-f <ficheiro>] [-e <ignore_pattern>] [-s]\
 [{-p <dir1[<dir2>...] | -v}]
-p : Protege e guarda informação acerca de um ou mais diretórios
-v : Verifica alterações em ficheiros desde que foram protegidos\
 sendo este modo escolido por defeito.
-f : Indicação do nome do ficheiro onde a base de dados será guardada\
 (Por defeito será /tmp/.pdb)
-e : Permite a exclusão de ficheiros voláteis (ex. *.tmp, *.log,
/tmp/*) da proteção e verificação
-s : Emissão de alertas de alta prioridade para o sistema de logging
usando o logger
EOF

}

# Valida os argumentos restantes: em proteção devem ser diretórios;
# em verificação não devem existir argumentos posicionais.
assert_valid_remaing_files(){
  if [[ $mode = "viguia" ]]; then
    if [[ $# -ne 0 ]]; then
      echo "erro: modo vigia não pode ter ficheiros para \
      guardar" >&2
      print_help >&2
      exit 1
    fi
  else
    if [[ $# -eq 0 ]];then
      echo "must be at least 1 file to protect">&2
      print_help >&2
      exit 1
    fi
    for argument in "$@"; do
      if ! [[ -d "$argument" ]]; then
        echo "there is no directory $argument">&2
        print_help >&2
        exit 1
      fi
      if [[ ! -r "$argument" || ! -x "$argument" ]]; then
        echo "error directory $argument must be readable \
        and executable">&2
        print_help >&2
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
      print_help >&2
      exit 1
    fi
    if ! [[ -r $logs_file ]]; then
      echo "the logs file must have reading permitions">&2
      print_help >&2
      exit 1
    fi
  else
    if [[ -e $logs_file ]]; then
      echo "In protection mode the file you are writing to must \
      not exist">&2
      print_help >&2
      exit 1
    fi

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
  local arguments=()
  local selected_mode=""
  # Percorre todos os argumentos, incluindo opções colocadas depois dos diretórios.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h) print_help; exit 0 ;;
      -p|-v)
        if [[ -n "$selected_mode" && "$selected_mode" != "$1" ]]; then
          echo "You cannot use -p and -v together" >&2
          print_help >&2
          exit 1
        fi
        selected_mode="$1"
        if [[ "$1" == -p ]]; then mode="protecao"; else mode="viguia"; fi
        shift ;;
      -f|-e)
        if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
          echo "Missing argument for $1" >&2
          print_help >&2
          exit 1
        fi
        if [[ "$1" == -f ]]; then logs_file="$2"; else pathern_to_ignore="$2"; ignore_given=true; fi
        shift 2 ;;
      -s) is_output_to_log=true; shift ;;
      -*) echo "Invalid option $1" >&2; print_help >&2; exit 1 ;;
      *) arguments+=("$1"); shift ;;
    esac
  done
  logs_file=$(realpath -m -- "$logs_file") || exit 1
  assert_valid_remaing_files "${arguments[@]}"
  assert_logs_file "$logs_file"
  if [[ "$mode" == viguia ]]; then
    view_mode
  else
    protect_mode "${arguments[@]}"
  fi
}

protect_mode(){
  local folder file list count=0
  # Guarda os caminhos numa lista para remover duplicados antes de os processar.
  list=$(mktemp) || exit 1
  touch "$logs_file" || { echo "there was an error while creating the logs file" >&2; exit 1; }
  save_header
  # Regista o padrão para aplicar a mesma exclusão durante a verificação.
  printf '#ignore,%s\n' "$pathern_to_ignore" >> "$logs_file"
  for folder in "$@"; do
    protect_folder "$folder" || { rm -f -- "$logs_file"; exit 1; }
    if [[ $is_output_to_log = true ]]; then
      logger --priority info "$folder was saved"
    fi
  done
  sort -u -o "$list" "$list" || exit 1
  while IFS= read -r file; do
    [[ "$file" == "$logs_file" || "$file" == "$list" ]] && continue
    should_ignore "$file" && continue
    save_file_metadata "$file" || { rm -f -- "$logs_file"; exit 1; }
    count=$((count + 1))
  done < "$list"
  chmod 400 "$logs_file" || exit 1
  echo "Protection database $logs_file created successfully."
  echo "Files processed: $count"
  printf 'Protected directory: %s\n' "$@"
  rm -f -- "$list"
}

# $1 -> directory to protect
protect_folder(){
  local folder
  folder=$(realpath -e -- "$1") || return 1
  # Guarda o diretório protegido e reúne os ficheiros que contém.
  printf '#dir,%s\n' "$folder" >> "$logs_file" || return 1
  find "$folder" -type f -print >> "$list"
}

should_ignore(){
  local file="$1"
  # Aceita o padrão glob aplicado ao nome do ficheiro ou ao caminho completo.
  [[ -n "$pathern_to_ignore" && ( "${file##*/}" == $pathern_to_ignore || "$file" == $pathern_to_ignore ) ]]
}

save_header(){
  echo "user_id,group_id,size,permitions,modification_date,\
  file_type,sha256,file_path" > "$logs_file"
}

# $1 file to save the metadata
save_file_metadata(){
  local file="$1" sha256
  sha256=$(sha256sum "$file" | awk '{print $1}')
  stat --format="%u,%g,%s,%a,%y,%F,$sha256,$file" -- "$file" >> "$logs_file"
}

view_mode(){
  local line folder file list original_pattern
  local -a folders=()
  original_pattern="$pathern_to_ignore"
  # Reutiliza o padrão guardado durante a proteção.
  pathern_to_ignore=$(sed -n '2s/^#ignore,//p' "$logs_file")
  if [[ "$ignore_given" == true && "$original_pattern" != "$pathern_to_ignore" ]]; then
    echo "The exclusion must match the pattern in the database" >&2
    print_help >&2
    exit 1
  fi
  # Recupera os diretórios protegidos para voltar a percorrê-los.
  while IFS= read -r line; do
    [[ "$line" == '#dir,'* ]] && folders+=("${line#\#dir,}")
  done < "$logs_file"
  if [[ ${#folders[@]} -eq 0 ]]; then
    echo "Invalid database: no protected directories" >&2
    print_help >&2
    exit 1
  fi
  list=$(mktemp) || exit 1
  # Cria a lista atual para que os ficheiros novos também sejam detetados.
  for folder in "${folders[@]}"; do
    [[ ! -e "$folder" ]] && continue
    if [[ ! -d "$folder" ]] || ! find "$folder" -type f -print >> "$list"; then
      echo "Cannot inspect directory: $folder" >&2
      exit 1
    fi
  done
  sort -u -o "$list" "$list" || exit 1
  n_correct_files=0
  n_ignored_files=0
  n_deleted_files=0
  n_added_files=0
  n_changued_files=0
  while IFS= read -r line; do
    [[ "$line" == '#'* || "$line" == 'user_id,'* || -z "$line" ]] && continue
    validate_arguments "$line"
  done < "$logs_file"
  verify_new_files_in_directory "$list"
  echo "final report:"
  echo "number files read correctly $((n_correct_files))"
  echo "number files deleted $n_deleted_files"
  echo "number added files $n_added_files"
  echo "number changed files $n_changued_files"
  echo "number ignored files $n_ignored_files"
  if [[ $is_output_to_log = true ]] && ( [[ $n_added_files -ne 0 ]] || [[ $n_deleted_files -ne 0 ]] || [[ $n_changued_files -ne 0 ]] ); then
    logger --priority alert "Alert protect directories where compromised."
  fi
  rm -f -- "$list"
}

validate_arguments(){
  line="$1"
  IFS=, read -r stored_user_id stored_goup_id stored_size stored_permitions stored_mod_date stored_file_type stored_sha256 stored_file_truepath <<< "$line"
  if should_ignore "$stored_file_truepath"; then
    ((n_ignored_files++))
    return 0
  fi
  # Verifica a existência antes de executar stat ou calcular o hash.
  if [[ ! -e "$stored_file_truepath" ]]; then
    echo "the file $stored_file_truepath is currently not in the system"
    echo "  Initial information: $line"
    ((n_deleted_files++))
    return 0
  fi
  if [[ ! -f "$stored_file_truepath" || ! -r "$stored_file_truepath" ]]; then
    echo "Cannot read file: $stored_file_truepath" >&2
    exit 1
  fi
  real_user_id="$(stat --format="%u" "$stored_file_truepath")"
  real_group_id="$(stat --format="%g" "$stored_file_truepath")"
  real_size="$(stat --format="%s" "$stored_file_truepath")"
  real_permitions="$(stat --format="%a" "$stored_file_truepath")"
  real_mod_date="$(stat --format="%y" "$stored_file_truepath")"
  real_file_type="$(stat --format="%F" "$stored_file_truepath")"
  if [[ -d $stored_file_truepath ]];then 
    real_sha256="n\a"
  else
    real_sha256="$(sha256sum < "$stored_file_truepath")" || exit 1
    real_sha256="${real_sha256%% *}"
  fi
  current_file_was_modified=false
  new_file_added=false

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
  if [[ $current_file_was_modified = true ]]; then
    echo "  Initial information: $line"
    echo "  Current information: USER=$real_user_id GROUP=$real_group_id SIZE=$real_size PERM=$real_permitions DATE=$real_mod_date SHA256=$real_sha256"
  fi
  if [[ $current_file_was_modified = false ]] && [[ $new_file_added = false ]]; then
    ((n_correct_files++))
  elif [[ $current_file_was_modified != false ]]; then
    ((n_changued_files++))
  fi
}


# $1 dir 
verify_new_files_in_directory(){
  local file database_line saved_uid saved_gid saved_size saved_permissions saved_date saved_type saved_hash saved_path found
  while IFS= read -r file; do
    [[ "$file" == "$logs_file" || "$file" == "$list" ]] && continue
    should_ignore "$file" && continue
    found=false
    while IFS= read -r database_line; do
      [[ "$database_line" == '#'* || "$database_line" == 'user_id,'* || -z "$database_line" ]] && continue
      IFS=, read -r saved_uid saved_gid saved_size saved_permissions saved_date saved_type saved_hash saved_path <<< "$database_line"
      # Compara o caminho completo para evitar correspondências parciais.
      if [[ "$saved_path" == "$file" ]]; then
        found=true
        break
      fi
    done < "$logs_file"
    if [[ "$found" == false ]]; then
      ((n_added_files++))
      echo "$file is NEW"
      echo "  Current information: $(stat --format='USER=%U GROUP=%G SIZE=%s PERM=%a DATE=%y' -- "$file") SHA256=$(sha256sum < "$file" | awk '{print $1}')"
    fi
  done < "$1"
}

parseArgs "$@"
