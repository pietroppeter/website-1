# vim: set ts=2 sw=2 et ai ft=ruby:

def relpath(from, to)
  raise "from may not be nil" if from.nil?
  raise "to may not be nil" if to.nil?
  require 'pathname'
  src_path = Pathname.new(from)
  dst_path = Pathname.new(to)
  if src_path.to_s[-1,1] != '/'
    rp = dst_path.relative_path_from(src_path.dirname).to_s
  else
    rp = dst_path.relative_path_from(src_path).to_s
  end
  if dst_path.to_s[-1,1] == '/'
    rp << '/'
  end
  if rp =~ %r{^(.+)(#[^/]+)$} then
    rp = $1
    balise = $2
  else
    balise = nil
  end
  rp << 'index.html' if rp[-1,1] == '/'
  rp << balise unless balise.nil?
  rp
end

