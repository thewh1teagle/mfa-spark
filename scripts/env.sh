if [ -n "${BASH_SOURCE:-}" ]; then
  _mfa_env_source="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _mfa_env_source="${(%):-%N}"
else
  echo "scripts/env.sh must be sourced from bash or zsh" >&2
  return 1 2>/dev/null || exit 1
fi

_mfa_scripts_dir="$(cd "$(dirname "$_mfa_env_source")" && pwd)"
_mfa_root="$(cd "$_mfa_scripts_dir/.." && pwd)"
source "$_mfa_scripts_dir/versions.env"

export PREFIX="$_mfa_root/opt"
export SRC="$_mfa_root/src"
export KALDI_ROOT="$_mfa_root/src/kaldi"
export PATH="$PREFIX/bin:$KALDI_ROOT/tools/openfst/bin:$PATH"
for _mfa_bin_dir in "$KALDI_ROOT"/src/*bin "$KALDI_ROOT"/src/bin; do
  if [ -d "$_mfa_bin_dir" ]; then
    export PATH="$_mfa_bin_dir:$PATH"
  fi
done
export LD_LIBRARY_PATH="$PREFIX/lib:$KALDI_ROOT/src/lib:$KALDI_ROOT/tools/OpenBLAS/install/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPLUS_INCLUDE_PATH="$PREFIX/include:${CPLUS_INCLUDE_PATH:-}"
export LIBRARY_PATH="$PREFIX/lib:${LIBRARY_PATH:-}"

unset _mfa_env_source _mfa_scripts_dir _mfa_root _mfa_bin_dir
