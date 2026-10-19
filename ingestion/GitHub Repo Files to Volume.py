# Databricks notebook source
# DBTITLE 1,Title
# MAGIC %md
# MAGIC # GitHub Repo Files to Volume
# MAGIC
# MAGIC Downloads files from the GitHub repository `amol-telang/Dataset` (Sample directory, main branch) and copies them to the Databricks Unity Catalog volume `/Volumes/databricks_sample/default/raw_landing`.

# COMMAND ----------

# DBTITLE 1,Create Volume
# Create the Unity Catalog volume if it doesn't already exist
# The catalog (databricks_sample) and schema (default) must exist beforehand

volume_path = "/Volumes/databricks_sample/default/raw_landing"

try:
    spark.sql("CREATE VOLUME IF NOT EXISTS databricks_sample.default.raw_landing")
    print(f"Volume ready: {volume_path}")
except Exception as e:
    print(f"Could not create volume: {e}")
    print("Ensure the catalog 'databricks_sample' and schema 'default' exist and you have permissions.")
    raise

# COMMAND ----------

# DBTITLE 1,Clone GitHub Repo
import subprocess
import tempfile
import os

# GitHub repository details
repo_url = "https://github.com/amol-telang/Dataset.git"
branch = "main"
subdirectory = "Sample"

# Clone the repo (shallow clone for speed) into a temp directory
clone_dir = tempfile.mkdtemp()
print(f"Cloning {repo_url} (branch: {branch}) into {clone_dir} ...")

result = subprocess.run(
    ["git", "clone", "--depth", "1", "--branch", branch, repo_url, clone_dir],
    capture_output=True, text=True
)

if result.returncode != 0:
    print(f"git clone failed:\n{result.stderr}")
    raise RuntimeError(f"git clone failed: {result.stderr}")
else:
    print("Clone successful!")

# Path to the Sample directory in the cloned repo
sample_dir = os.path.join(clone_dir, subdirectory)
if not os.path.isdir(sample_dir):
    print(f"ERROR: Directory '{subdirectory}' not found in cloned repo.")
    # List what's in the repo root for debugging
    print(f"Contents of repo root: {os.listdir(clone_dir)}")
    raise FileNotFoundError(f"Directory '{subdirectory}' not found in cloned repo")

# List all files in the Sample directory (including subdirectories)
all_files = []
for root, dirs, filenames in os.walk(sample_dir):
    for filename in filenames:
        full_path = os.path.join(root, filename)
        rel_path = os.path.relpath(full_path, sample_dir)
        all_files.append((rel_path, full_path))

print(f"\nFound {len(all_files)} file(s) in '{subdirectory}/':")
for rel_path, full_path in all_files:
    size = os.path.getsize(full_path)
    print(f"  - {rel_path} ({size} bytes)")

# COMMAND ----------

# DBTITLE 1,Download and Copy to Volume
import shutil

volume_base = "/Volumes/databricks_sample/default/raw_landing"

# Ensure the volume directory exists
dbutils.fs.mkdirs(volume_base)

copied_files = []

for rel_path, full_path in all_files:
    file_name = os.path.basename(rel_path)
    
    # If file is in a subdirectory, preserve the subdirectory structure in the volume
    if os.path.dirname(rel_path):
        # Create subdirectory in the volume
        subdir = f"{volume_base}/{os.path.dirname(rel_path)}"
        dbutils.fs.mkdirs(subdir)
        target_path = f"{volume_base}/{rel_path}"
    else:
        target_path = f"{volume_base}/{file_name}"
    
    file_size = os.path.getsize(full_path)
    
    # Copy the file to the volume
    with open(full_path, "rb") as src:
        with open(target_path, "wb") as dst:
            dst.write(src.read())
    
    copied_files.append(rel_path)
    print(f"Copied: {rel_path} ({file_size} bytes) -> {target_path}")

print(f"\nAll done! Copied {len(copied_files)} file(s) to {volume_base}")

# COMMAND ----------

# DBTITLE 1,Verify Copied Files
# List files in the volume to verify they were copied successfully
print(f"Files in {volume_base}:")
print("=" * 60)

volume_files = dbutils.fs.ls(volume_base)
for f in volume_files:
    print(f"  {f.name}  ({f.size} bytes)")

print(f"\nTotal files in volume: {len(volume_files)}")
print(f"Files copied from GitHub: {len(copied_files)}")

# Cross-check
volume_names = {f.name for f in volume_files}
github_names = set(copied_files)
missing = github_names - volume_names
if missing:
    print(f"\nWARNING: Missing files: {missing}")
else:
    print("\nAll files verified successfully!")
