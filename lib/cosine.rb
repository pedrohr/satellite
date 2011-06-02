#calculates the cosine distance between two strings st1 and st2
def cosine_distance(st1, st2)
  freq1 = Hash.new(0)
  freq2 = Hash.new(0)

  #calculate the frequency vector
  st1.split(//).each do |v|
    freq1[v] += 1
  end
  st2.split(//).each do |v|
    freq2[v] += 1
  end

  #optimizes future comparisons
  if freq1.size < freq2.size
    base = freq1
    compare = freq2
  else
    base = freq2
    compare = freq1
  end
  
  sum_base = 0
  sum_compare = 0
  dot_prod = 0

  #compute the dot product and the squared sum of the vector base
  base.each_pair do |key, value|
    sum_base += value * value
    image = compare[key]
    dot_prod += value * image
    sum_compare += image * image
    compare.delete(key)
  end

  compare.each_pair do |key,value|
    sum_compare += value * value
  end

  dot_prod/Math.sqrt(sum_base*sum_compare)
end
