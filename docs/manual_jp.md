# 📦 インストール

## 必要なソフトウェア

| カテゴリ | ソフトウェア・ライブラリ | バージョン |
|---|---|---|
| **言語** | Bash | 4.0 以上 |
| | Python | 3.11 以上 |
| **MDエンジン** | GROMACS | 2021.0 以上 |
| | Amber | 22.0 以上 |
| **ツール** | AmberTools | 22.0 以上 |
| | PROCHECK | |
| | ColabFold (任意) | |
| **ライブラリ** | MDAnalysis | |
| | deeptime | |
| | scikit-learn | |
| | pandas | |
| | numpy | |
| | matplotlib | |
| | ParmEd | |

## インストール手順

本ツールの実行には **Conda（Miniconda / Anaconda）環境の構築が必須** です。

```bash
git clone https://github.com/mikant2/AI-Assisted_OFLOOD.git
cd AI-Assisted_OFLOOD

conda env create -f environment.yml
conda activate AI-Assisted_OFLOOD
./setup.sh
```

> [!NOTE]
> `conda env create` が失敗した場合、[🔧 トラブルシューティング](#-トラブルシューティング)をご参照ください。

## インストールの確認

```bash
python3 -c "import MDAnalysis, deeptime, sklearn, pandas, parmed; print('OK')"
bash --version
gmx --version   # またはAmberの場合: pmemd --version
```

# ⚙️ プロジェクト設定

本マニュアルではGROMACSを用いた場合（`base_project_for_gromacs`）を解説します。Amberを使用する（`base_project_for_amber`）場合は、拡張子やディレクトリ名を適宜読み替えてください。

（例：`GROMACS` → `AMBER`、`mdp/` → `mdin/`、`.top/.gro` → `.prmtop/.inpcrd`）

## ディレクトリ構造

```bash
my_project/
├── run.sh*                 # 実行ファイル、パス定義、アミノ酸配列の入力
├── para_conf.sh            # 全設定パラメータ
├── user_scripts/
│   ├── prepare_md.sh       # Stage 2   入力
│   ├── minimize.sh         # Stage 4   入力
│   └── compute_cv.sh       # Stage 5/6 入力
│── mdp/
│   ├── sampling.mdp        # Stage 5   入力
│   └── production.mdp      # Stage 6   入力
├── inputs/
│   └── prediction/         # Stage 1   AI予測構造の配置場所
└── outputs/
    ├── prepared_systems/   # Stage 2   出力
    ├── unified_systems/    # Stage 3   出力
    ├── relaxed_systems/    # Stage 4   出力
    ├── oflood/             # Stage 5   出力
    ├── production/         # Stage 6   出力
    └── msm_analysis/       # Stage 7   出力
```

## ステップ 1: テンプレートのコピー

`templates` ディレクトリ内の`base_project_for_gromacs`を任意の作業ディレクトリ（例: `my_project`）へコピーしてください。

```bash
cp -r /path/to/AI-Assisted_OFLOOD/templates/base_project_for_gromacs/ /path/to/my_project/
cd my_project/
```

## ステップ 2: `run.sh` の編集

`my_project`ディレクトリ内の`run.sh`を開き、下記を編集してください。

本レポジトリの絶対パスを`AA_OFLOOD_ROOT`と定義してください。

```bash
AA_OFLOOD_ROOT="/path/to/AI-Assisted_OFLOOD"
```

Condaがインストールされているルートディレクトリ（MiniforgeやAnaconda等）の絶対パスを`CONDA_DIR`と定義してください。

```bash
CONDA_DIR="/path/to/conda"
```

GROMACSの絶対パスを`GROMACS_DIR`と定義してください。

```bash
GROMACS_DIR="/path/to/gromacs"
```

> [!NOTE]
> Stage 1でcolabfoldによるAI予測構造の自動生成を使用する場合は[localcolabfold](https://github.com/YoshitakaMo/localcolabfold)をインストールし、その絶対パスを`COLABFOLD_DIR`と定義してください。
>
>```bash
>COLABFOLD_DIR="/path/to/colabfold"
>```
>
>また、ターゲットタンパク質のアミノ酸配列を`SEQUENCE`と定義してください。
>
>```bash
>SEQUENCE="KDTIALVVSTLN..."
>```

> [!TIP]
> 多量体（マルチマー）を計算する場合は、各モノマーの配列をコロン（`:`）で区切って入力してください。内部の ColabFold が自動的に AlphaFold-Multimer として処理します。（例: `SEQUENCE="SEQ1:SEQ2"`）
> ただし、低分子リガンド等には対応していません。詳細は[トラブルシューティング](#リガンドを含む複合体系を計算したい)をご参照ください。

## ステップ 3: `para_conf.sh` の編集

すべてのシミュレーション設定は`para_conf.sh`に集約されます。`my_project`ディレクトリ内の`para_conf.sh`を開き、下記を編集してください。

### 1. MD エンジンの指定

使用するMD エンジン（`"gromacs"` または `"amber"`）と、その実行コマンド名（例: `gmx` や `gmx_mpi`）を指定します。

```bash
ENGINE="gromacs"
GMX_CMD="gmx_mpi"
```

### 2. ユーザースクリプトの指定

Stage 2（モデリング）、Stage 4（エネルギー最小化）、Stage 5・6（collective variables計算）で使用されるユーザースクリプトへの絶対パスを指定します。

```bash
BUILD_MD_SYSTEM_FILE="${PROJECT_DIR}/user_scripts/prepare_md.sh"
MINIMIZE_SCRIPT_FILE="${PROJECT_DIR}/user_scripts/minimize.sh"
COMPUTE_CV_SCRIPT_FILE="${PROJECT_DIR}/user_scripts/compute_cv.sh"
```

### 3. HPC アダプタの指定

HPC ジョブ投入時に使用するHPCアダプタスクリプトを指定します。

```bash
SUBMIT_SCRIPT_FILE="${AA_OFLOOD_ROOT}/submit_scripts/template.sh"
```

### 4. 並列処理数の指定

HPC ジョブ以外の処理における最大同時実行数を指定します。

```bash
MAX_PARALLEL="8"
```

### 5. MD 入力ファイルの指定

Stage 5（サンプリング）と Stage 6（プロダクションラン）で使用するMDパラメータファイル（`.mdp` または `.in`）をそれぞれ指定します。

```bash
SAMPLING_PARAM_FILE="${PROJECT_DIR}/mdp/sampling.mdp"
PRODUCTION_PARAM_FILE="${PROJECT_DIR}/mdp/production.mdp"
```

### 6. OFLOOD サイクルパラメータの指定

Stage 5（サンプリング）および Stage 6（プロダクション）における、最大サイクル数と1サイクルあたりのMDジョブ（シード）数を設定します。また、`compute_cv.sh` が出力する集団変数の次元数（`N_CV`）を指定します。

```bash
MAX_SAMPLING_CYCLES="5"
SAMPLING_SEEDS_PER_CYCLE="50"
MAX_PRODUCTION_CYCLES="2"
PRODUCTION_SEEDS_PER_CYCLE="30"
N_CV="2"
```

### 7. シード選択パラメータの指定

DBSCAN クラスタリングにおけるクラスター半径（`CLUSTER_EPS`）およびコア点となるための最小データ数（`CLUSTER_MIN_SAMPLES`）をそれぞれ指定します。

```bash
CLUSTER_EPS="0.6"
CLUSTER_MIN_SAMPLES="15"
```

PROCHECK による構造の品質評価に使用する G-factor の閾値を指定します。この値を下回る（品質が低い）構造は、次サイクルのシード候補から厳格に除外されます。

```bash
G_FACTOR="-0.50"
```

### 8. マルコフ状態モデル（MSM）パラメータの指定

クラスター数（`MSM_N_CLUSTERS`）およびラグタイム（ステップ数: `MSM_LAGTIME`）に加え、
Implied timescale 評価用のラグタイムのリスト（`MSM_LAG_LIST`）、および Chapman-Kolmogorov テストの評価状態数（`MSM_CK_STATES`）を指定します。

```bash
MSM_N_CLUSTERS="100"
MSM_LAGTIME="100"
MSM_LAG_LIST="1 10 100 500 1000 1500 2000"
MSM_CK_STATES="4"
```

### 9. 描画・プロットパラメータの指定

自由エネルギー地形およびサンプリングの様子を描画する際に使用する軸ラベル（`CV_X_LABEL`、`CV_Y_LABEL`）、およびサンプリングモニター（`--plot`）の収束判定に用いるグリッド分割数（`GRID_BINS`）を指定します。

```bash
CV_X_LABEL="CV 1"
CV_Y_LABEL="CV 2"
GRID_BINS="20"
```

## ステップ 4: ユーザースクリプトの編集

`user_scripts/` 内の3つのスクリプトを、研究対象に合わせて実装してください。
各スクリプトのインターフェース（引数・期待出力）の詳細は [📝 ユーザースクリプト リファレンス](#-ユーザースクリプト-リファレンス) を参照してください。

## ステップ 5: HPCアダプタの設定

MDジョブの投入方法を設定します。詳細は [🖥️ HPCアダプタ設定](#️-hpcアダプタ設定) を参照してください。

# 🔬 ステージリファレンス

以下の図はワークフロー全体の流れを示しています:

<p align="center">
  <img src="../workflow_figure.png" width="720" alt="AI-Assisted OFLOOD ワークフロー">
</p>

## 実行方法

```bash
./run.sh <ステージ番号>      # 単一ステージ
./run.sh <番号1> <番号2> …   # 複数ステージを順番に実行
./run.sh all                 # ステージ 1〜7 を全て実行
./run.sh --plot 5 6          # Stage 5，6 をサイクルごとのプロット付きで実行
```

※ `./run.sh --help` でコマンドオプションの一覧を確認できます。

---

## Stage 1: AI_Modeling

| 項目 | 内容 |
|------|------|
| **入力** | なし（または `inputs/prediction/` に **PDB フォーマット**の構造ファイル） |
| **出力** | `inputs/prediction/model_001.pdb`, `model_002.pdb`, … |
| **ユーザースクリプト** | なし（自動） |
| **主要パラメータ** | なし |

内蔵の `run_colabfold.sh` を使用してColabFoldを実行します。`inputs/prediction/` に **PDB フォーマット**（`.pdb`）のファイルが既に存在する場合は、構造予測は自動的にスキップされ、リネーム処理のみが行われます。配列にコロン（`:`）が含まれている場合は多量体として予測されます。ただし、低分子リガンドや非標準アミノ酸の予測には対応していません。それらを含む系を計算したい場合は、[トラブルシューティング](#リガンドを含む複合体系を計算したい)を参照してください。

> [!TIP]
> AI予測構造は **任意のツール**（AlphaFold, ESMFold 等）で生成したものを使用できます。ColabFold連携は自動化のための便利機能であり、必須ではありません。`inputs/prediction/` に **PDB フォーマット**の構造ファイルを配置するだけで Stage 2 以降に進めます。

> [!NOTE]
> 内蔵の ColabFold 連携（`run_colabfold.sh`）を使用した場合、構造は**我々の論文**（Aoki & Harada, 2026, *J. Phys. Chem. Lett.*）と同一の条件、すなわち models=5、seeds=16、recycles=3、`--max-msa 16:32` で生成されます。これらのパラメータは本リポジトリの設計方針として固定されています。本リポジトリは任意の AI モデルを対象とした汎用的なワークフローであり、ColabFold 専用のパラメータ調整には特化していません。ColabFold の詳しい使い方（カスタムモデルや MSA 設定など）については、[LocalColabFold 公式ドキュメント](https://github.com/YoshitakaMo/localcolabfold)をご参照ください。

---

## Stage 2: System_Preparation

| 項目 | 内容 |
|------|------|
| **入力** | `inputs/prediction/*.pdb` |
| **出力** | `outputs/prepared_systems/topology/`, `outputs/prepared_systems/coordinates/` |
| **ユーザースクリプト** | `user_scripts/prepare_md.sh` |
| **主要パラメータ** | `BUILD_MD_SYSTEM_FILE`, `MAX_PARALLEL` |

各 PDB に対してユーザースクリプトを並列実行し、Gromacs形式（`.top`, `.gro`）またはAmber形式（`.prmtop`, `.inpcrd`）の系を構築します。両方のMDエンジンに完全対応しています。

---

## Stage 3: Unify_Atoms

| 項目 | 内容 |
|------|------|
| **入力** | `outputs/prepared_systems/` |
| **出力** | `outputs/unified_systems/coordinates/`, `outputs/unified_systems/topology/master_topology.*` |
| **ユーザースクリプト** | なし（自動） |
| **主要パラメータ** | なし |

OFLOOD では全サイクルを通じて**単一のトポロジファイル**を参照します。そのため、全座標ファイルの分子構成を統一します。
溶質の判定は MDAnalysis の `select_atoms("protein")` で動的に行うため、非標準残基名でも正しく機能します。非溶質残基は全系の中で最も少ない系に合わせて削減されます。

---

## Stage 4: Energy_Minimization

| 項目 | 内容 |
|------|------|
| **入力** | `outputs/unified_systems/` |
| **出力** | `outputs/relaxed_systems/*.gro`（または `*.ncrst`） |
| **ユーザースクリプト** | `user_scripts/minimize.sh` |
| **主要パラメータ** | `MINIMIZE_SCRIPT_FILE`, `MAX_PARALLEL` |

各座標ファイルに対してユーザースクリプトを並列実行し、エネルギー最小化を行います。具体的な最小化の手順はユーザースクリプト内で定義します。

> [!WARNING]
> HPC の**ログインノード**でエネルギー最小化を実行する場合は，共有リソースに負荷をかけないよう CPU スレッド数を明示的に制限してください．GROMACSの場合は `gmx_mpi mdrun` コマンドに `-ntmpi 1 -ntomp N`（N は 1〜4 程度の小さい値）を追加してください。具体的な記述例は `examples/` 以下のサンプルスクリプトを参照してください。

---

## Stage 5: OFLOOD_Sampling

| 項目 | 内容 |
|------|------|
| **入力** | `outputs/relaxed_systems/` |
| **出力** | `outputs/oflood/cycle_001/md_001/`, `cycle_001/md_002/`, … |
| **ユーザースクリプト** | `user_scripts/compute_cv.sh` |
| **主要パラメータ** | `SAMPLING_PARAM_FILE`, `MAX_SAMPLING_CYCLES`, `SAMPLING_SEEDS_PER_CYCLE`, `N_CV`, `CLUSTER_EPS`, `CLUSTER_MIN_SAMPLES`, `G_FACTOR` |

`MAX_SAMPLING_CYCLES` サイクルの適応的サンプリングを実行します。サイクル番号およびMDディレクトリ番号はすべて `1` から開始（1-indexed）されます。

各サイクル: シード構造準備 → 短時間MD並列実行 → CV計算 → CV蓄積 → DBSCAN外れ値選択

**サンプリングモニター（`--plot` オプション）:**

`--plot` を付加して実行すると、各サイクル完了時に以下の 2 種類の図を自動生成します:

```bash
./run.sh --plot 5
```

1. **サンプリング分布図**（`sampling_distribution.pdf`）— 現在のサイクルまでに探索された構造を CV 空間上に散布図として投影します。クラスタリング結果（Clustered / Outliers / Seeds）が色分けで表示されます。
2. **収束モニター図**（`sampling_convergence.pdf`）— サイクルごとの占有グリッドセル数の推移を対数スケールで表示し、探索の収束度を確認できます。グリッドの粗さは `GRID_BINS` で制御します。

生成された図は各サイクルの `analysis/` ディレクトリに保存されます。

<p align="center">
  <img src="./sampling_distribution.png" width="420" alt="サンプリング分布図の例">
  <img src="./sampling_convergence.png" width="420" alt="収束モニター図の例">
</p>

---

## Stage 6: OFLOOD_Production

| 項目 | 内容 |
|------|------|
| **入力** | `outputs/oflood/`（全サンプリング履歴 `cv_all.txt`） |
| **出力** | `outputs/production/cycle_001/md_001/`, `cycle_001/md_002/`, … |
| **ユーザースクリプト** | `user_scripts/compute_cv.sh` |
| **主要パラメータ** | `PRODUCTION_PARAM_FILE`, `MAX_PRODUCTION_CYCLES`, `PRODUCTION_SEEDS_PER_CYCLE` |

Stage 5 で探索された全CV空間（`cv_all.txt`）から `generate_seeds.py` によりシード構造が自動抽出され、`outputs/production/seeds/` に保存されます。
Stage 6 の Cycle 1 ではこの抽出されたシード群を出発点として長時間 MD を実行します。以降、`MAX_PRODUCTION_CYCLES` に基づき複数サイクルにわたってプロダクション MD が展開され、得られた全トラジェクトリが Stage 7 の MSM 解析に使用されます。

ステージ 5 と同様に `./run.sh --plot 6` でサンプリングモニター図を生成できます。詳細は Stage 5 を参照してください。

---

## Stage 7: MSM_Analysis

| 項目 | 内容 |
|------|------|
| **入力** | `outputs/oflood/` と `outputs/production/` の CV データ |
| **出力** | `outputs/msm_analysis/` |
| **ユーザースクリプト** | なし（自動） |
| **主要パラメータ** | `MSM_N_CLUSTERS`, `MSM_LAGTIME`, `MSM_LAG_LIST`, `MSM_CK_STATES` |

`libexec/scripts/msm_analysis.py` を 2 パスで実行します：

1. **Check モード** — implied timescale を `MSM_LAG_LIST` のラグタイムで計算し、適切なラグタイムを特定
2. **Run モード** — MSM を構築し、CK テスト・自由エネルギー地形（FEL）を生成

# 📝 ユーザースクリプト リファレンス

本リポジトリは「OFLOODのパイプラインを回すフレームワーク」であり、**具体的なMD系の構築ツール（tleap等）やCV計算ツール（cpptraj等）には一切制限を設けていません。**
`user_scripts/` ディレクトリ内のスクリプトは、パイプラインから渡される引数を受け取り、指定されたパスにファイルを出力することだけが求められる「インターフェース」です。具体的な実装例については、`examples/soluble_protein_for_gromacs/user_scripts/` などを参考にしてください。

## prepare_md.sh — Stage 2

PDB ファイルを受け取り、MD用のトポロジと座標ファイルを生成します。内部でどのツール（pdb2gmx, tleap, カスタムPythonスクリプト等）を呼び出しても構いません。

**インターフェース（パイプラインからの引数）:**

```bash
_pdb_file="${1}"   # 入力 PDB ファイルへのパス
_top_dir="${2}"    # トポロジファイルの出力先ディレクトリ
_crd_dir="${3}"    # 座標ファイルの出力先ディレクトリ
```

**期待される動作:**

- 最終的に `_top_dir` にトポロジファイル（`.top` または `.prmtop`）を保存する。
- 最終的に `_crd_dir` に座標ファイル（`.gro` または `.inpcrd`）を保存する。

## minimize.sh — Stage 4

系構築後のエネルギー最小化を実行します。

**インターフェース（パイプラインからの引数）:**

```bash
_crd_file="${1}"       # 最小化対象の座標ファイルへのパス
_target_top_file="${2}"# トポロジファイルへのパス
_output_dir="${3}"     # 出力先ディレクトリ
```

**期待される動作:**

- 最終的に `_output_dir` に緩和された座標ファイルを出力する。

## compute_cv.sh — Stage 5・6

MD トラジェクトリから集団座標（CV）を計算し、テキストとして出力します。

**インターフェース（パイプラインからの引数）:**

```bash
_traj_file="${1}"         # トラジェクトリファイルへのパス
_top_file="${2}"     # トポロジファイルへのパス
_structure_file="${3}"    # 構造ファイルへのパス
_out_file="${4}"          # CVデータの出力先ファイル
_cycle_id="${5}"     # 現在のサイクル番号
```

> [!IMPORTANT]
> **PBC（周期境界条件）の処理について**
> 渡されるトラジェクトリ（`_traj_file`）はシミュレーション直後の生のデータです。CVを正しく計算するため、スクリプト内で必ず PBC の処理（例：cpptraj の `autoimage` や、GROMACS の `trjconv -pbc mol` など）を行ってから抽出してください。

**期待される出力フォーマット (`_out` に書き込むデータ):**

```text
# cv1    cv2    ...    cycle  md_id  frame
  2.134  145.3  ...    1      1      0
  2.201  143.8  ...    1      1      1
```

カラム順: CV1, CV2, ..., CV_N (`para_conf.sh` の `N_CV` に対応), サイクル番号, MDラン番号, フレーム番号

## MD入力ファイル

### `mdp/sampling.mdp` （Amberの場合は `mdin/sampling.in`）

OFLOOD サイクル用の短 MD の設定ファイルです。

### `mdp/production.mdp` （Amberの場合は `mdin/production.in`）

選択されたシードから実施する長時間 MD の設定ファイルです。

# 🖥️ HPCアダプタ設定

パイプラインから発行されるMDジョブを、お手持ちのクラスター環境（PBS, Slurmなど）に投げるためのアダプタを設定します。

## アダプタの選択・作成

`submit_scripts/` にはいくつかのアダプタが含まれていますが、基本的には **`template.sh` をコピーしてご自身の環境用にカスタマイズする** ことを強く推奨します。

```bash
cp submit_scripts/template.sh submit_scripts/my_cluster.sh
```

## アダプタの関数一覧

各アダプタは、ジョブ投入や環境構築のための以下の関数を実装します：

| 関数 | 役割 |
|---|---|
| `setup_env_md()` | 環境構築（module load, GMXRC等） |
| `submit_md_job()` | 単一のMDコマンドをジョブとして投入し、ジョブIDをechoする |
| `current_running_jobs()` | 投入済みジョブIDのうち、まだ動いているものの数をechoする |
| `setup_env_ai()` | AI予測用の環境構築（オプション） |
| `submit_ai_job()` | AI予測ジョブの投入（オプション） |

## `setup_env_md()` のカスタマイズ

計算ノードで MD を実行するための環境ロードを記述します。例えば GROMACS を使用し、モジュールシステムが利用可能なクラスターでは以下のようになります：

```bash
setup_env_md() {
  module purge
  module load <your_mpi_module>
  source "${GROMACS_DIR}/bin/GMXRC"
}
```

使用するソフトウェアとクラスターのモジュールシステムに合わせて実装してください。

## `submit_md_job()` のカスタマイズ

単一の MD ランをバッチジョブとして投入します。heredoc 内の **`#PBS` ディレクティブ**と **`export` 行**をクラスター環境に合わせて編集してください。`mkdir -p` 以降の行は変更不要です。以下は NEC NQSV (Pegasus) 向けの実装例です：

```bash
cat >"${_tmp_script}" <<EOF
#!/usr/bin/env bash
#PBS -A ${HPC_GROUP}
#PBS -q ${HPC_QUEUE}
#PBS -l elapstim_req=${WALLTIME_MD}
#PBS -v OMP_NUM_THREADS=${HPC_NCPUS}
#PBS -N oflood_${_job_type}_$(basename "${_work_dir}")
#PBS -o ${_work_dir}/pbs.o
#PBS -e ${_work_dir}/pbs.e

export GROMACS_DIR="${GROMACS_DIR}"

mkdir -p "${_work_dir}"
source "${SUBMIT_SCRIPT_FILE}"
setup_env_md

cd "${_work_dir}" || exit 1
${_cmd[*]} > "${_work_dir}/mdrun.log" 2>&1
echo \$? > "${_work_dir}/.job_exit_code"
EOF
```

> [!NOTE]
> `#PBS` ディレクティブの構文はクラスターの PBS フレーバーによって異なります（例：実行時間の指定が `-l elapstim_req=` か `-l walltime=` かなど）。`miyabi_pbs.sh` も参考にしてください。

## `current_running_jobs()` のカスタマイズ

ジョブスケジューラに応じて、ジョブ状態確認コマンドを変更する必要があります。PBS 環境では `qstat`、Slurm 環境では `squeue` を使用します。また、ジョブ ID の正規表現（`grep -oE '[0-9]+'`）についても、クラスターの `qsub` 出力形式に合わせて適切に修正してください。

## AI 予測ジョブのカスタマイズ（オプション）

`setup_env_ai()` は基本的に変更不要です。ColabFold の実行に必要な NVIDIA ライブラリが自動的に検出され、GPU が利用されます。

`submit_ai_job()` については、`submit_md_job()` と同様に heredoc 内の `#PBS` ディレクティブをクラスター環境に合わせて編集してください。

## 並列処理の制御

| 変数 | 設定ファイル | 意味 |
|---|---|---|
| `MAX_PARALLEL` | `para_conf.sh` | Stage 2・4 での並列ジョブ数（系構築・最小化） |
| `MAX_CONCURRENT_JOBS` | アダプタスクリプト | OFLOOD サイクルあたりの並列 MD 実行数（Stage 5・6） |
| `HPC_NCPUS` | アダプタスクリプト | PBS ジョブなどで要求するコア数 |

# 🔧 トラブルシューティング

## conda環境構築の失敗

**A:** `conda-forge` が `linux-aarch64` 向けのいくつかのバイナリ(Ambertoolsやpyemma)を提供していない可能性があります。

**対処法:**

1. `environment.yml` を開き、`dependencies` 中の該当ツールを削除します。
2. 再度 `conda env create -f environment.yml` を実行します。
3. 該当ツールを`pip`コマンドまたはソースコードから入手します。
4. パイプライン実行時はconda 環境のアクティベートに加え、手動インストールした該当ツールへのパスを忘れずに通してください。

## 自分で生成した構造を使いたい

**A:** `inputs/prediction/` に **PDB フォーマット**の構造ファイルを配置するだけで、Stage 1 から始めても自動的に構造生成プロセスはスキップされ、リネームのみが行われます。

```bash
mkdir -p my_project/inputs/prediction/
cp /path/to/my_structures/*.pdb my_project/inputs/prediction/
./run.sh 1 2
```

## リガンドを含む複合体系を計算したい

**A:** OFLOOD は拡張性が高く、ビルトインの構造予測（Stage 1）を使わずに独自の初期構造を利用することで、リガンドを含む系にも柔軟に対応できます。以下のワークフローで実行してください：

1. **初期構造の用意:** ドッキングソフト等でリガンドが結合した PDB ファイルを別途作成し、`inputs/prediction/` 内に配置します（これにより配列からの構造予測はスキップされます）。
2. **力場とトポロジーのカスタマイズ:** 外部ツール（Antechamber 等）を用いてリガンドのパラメータ（GAFF 等）を作成します。その後、`user_scripts/prepare_md.sh` を編集し、リガンドのパラメータファイルを `tleap` 等で読み込む処理を追記してください。

## DBSCANでアウトライアーが見つからない

**A:** `para_conf.sh` の `CLUSTER_EPS` を大きくしてください。
