for file in *.fs; do
    mv -- "$file" "${file%.fs}.fs.txt"
done