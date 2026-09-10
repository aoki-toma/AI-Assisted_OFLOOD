#!/usr/bin/env bash
# File: extract_frames.sh
# Description: Helper module to extract structure frames from MD trajectories based on selected seeds.

extract_frames_from_seeds() {
  local _engine=""
  local _selected_seeds_file=""
  local _src_root_dir=""
  local _target_dir=""
  local _frame_dt_ps=""
  local _is_production="false"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --engine)
      _engine="$2"
      shift 2
      ;;
    --seed-file)
      _selected_seeds_file="$2"
      shift 2
      ;;
    --work-root)
      _src_root_dir="$2"
      shift 2
      ;;
    --out-dir)
      _target_dir="$2"
      shift 2
      ;;
    --frame-dt-ps)
      _frame_dt_ps="$2"
      shift 2
      ;;
    --top-file)
      _top_file="$2"
      shift 2
      ;;
    --is-production)
      _is_production="$2"
      shift 2
      ;;
    *)
      msg_error "Unknown parameter passed: $1"
      exit 1
      ;;
    esac
  done

  if [[ -z "${_engine}" || -z "${_selected_seeds_file}" || -z "${_src_root_dir}" || -z "${_target_dir}" || -z "${_frame_dt_ps}" ]]; then
    msg_error "Usage: extract_frames_from_seeds --engine <engine> --seed-file <file> --work-root <dir> --out-dir <dir> --frame-dt-ps <dt> [--is-production true/false]"
    return 1
  fi
  local _traj_file_name=""
  local _output_ext=""
  local _gmx_cmd="${GMX_CMD:-gmx}"
  local -i _idx=1
  local -a _sel_parts=()
  local _sel_cycle="" _sel_md="" _sel_frame=""
  local _src_cycle_dir=""
  local _src_md_dir=""
  local _output_file=""
  local _md_dir=""
  local _time_ps=""
  local -i _amber_frame=0
  local _cpptraj_script=""

  require_file "${_selected_seeds_file}"
  require_dir "${_target_dir}"

  if [[ "${_engine}" == "gromacs" ]]; then
    _traj_file_name="md.xtc"
    _top_file="md.tpr"
    _output_ext="gro"
    require_cmds "${_gmx_cmd}"
  elif [[ "${_engine}" == "amber" ]]; then
    _traj_file_name="md.nc"
    _output_ext="ncrst"
    require_cmds cpptraj
    if [[ -z "${_top_file}" ]]; then
      msg_error "Amber engine requires --top-file to be set."
      return 1
    fi
  else
    msg_error "Unknown engine for extraction: ${_engine}"
    return 1
  fi

  while read -r -a _sel_parts; do
    [[ ${#_sel_parts[@]} -eq 0 || "${_sel_parts[0]}" =~ ^# ]] && continue
    _sel_cycle="${_sel_parts[-3]}"
    _sel_md="${_sel_parts[-2]}"
    _sel_frame="${_sel_parts[-1]}"

    printf -v _src_cycle_dir "%s/cycle_%03d" "${_src_root_dir}" "${_sel_cycle}"
    printf -v _src_md_dir "%s/md_%03d" "${_src_cycle_dir}" "${_sel_md}"
    require_file "${_src_md_dir}/${_traj_file_name}"

    if [[ "${_is_production}" == "true" ]]; then
      printf -v _output_file "%s/seed_%03d.%s" "${_target_dir}" "${_idx}" "${_output_ext}"
    else
      printf -v _md_dir "%s/md_%03d" "${_target_dir}" "${_idx}"
      mkdir -p "${_md_dir}"
      _output_file="${_md_dir}/mdin.${_output_ext}"
    fi

    if [[ "${_engine}" == "gromacs" ]]; then
      require_file "${_src_md_dir}/${_top_file}"
      _time_ps=$(awk -v f="${_sel_frame}" -v dt="${_frame_dt_ps}" 'BEGIN { printf "%.3f", f * dt }')

      ${_gmx_cmd} trjconv \
        -f "${_src_md_dir}/${_traj_file_name}" \
        -s "${_src_md_dir}/${_top_file}" \
        -o "${_output_file}" \
        -dump "${_time_ps}" <<<0 >/dev/null 2>&1 || {
        msg_error "Failed to extract GROMACS seed from ${_src_md_dir}/${_traj_file_name}"
        return 1
      }
    else
      _amber_frame=$((_sel_frame + 1))
      _cpptraj_script="${_src_md_dir}/.extract_seed_${_idx}.in"

      cat <<EOF >"${_cpptraj_script}"
parm ${_top_file}
trajin ${_src_md_dir}/${_traj_file_name} ${_amber_frame} ${_amber_frame}
trajout ${_output_file}
go
EOF
      if ! cpptraj "${_cpptraj_script}" >/dev/null 2>&1; then
        msg_error "Failed to extract Amber seed from ${_src_md_dir}/${_traj_file_name}"
        rm -f "${_cpptraj_script}"
        return 1
      fi
      rm -f "${_cpptraj_script}"
    fi

    ((_idx++)) || true
  done <"${_selected_seeds_file}"
}
