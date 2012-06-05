# vim: set ts=2 sw=2 et ai ft=ruby:

def make_headlines
  @items.select{|item| item.news? }.each do |item|
    fqid = item.id
    if item.identifier =~ %r,(^/news/)(\d{4}-\d{2}-\d{2})-(.+)$, then
      #item.identifier = $1 + $3
      item[:kind] = 'article'
      item[:created_at] = Time.parse($2)

      id = "/headlines/#{fqid}"
      attrs = item.attributes.reject {|k,v| k == :filename or k == :file}
      attrs[:kind] = 'headline'

      content = item.raw_content
      headline_content = content
      begin
        if content =~ /^(.+)---\s*MORE\s*---\s*$(.+)/m then
          headline_content = $1
          content = $1 + $2
          #item.raw_content = content
          attrs[:readmore] = item.identifier
        elsif content =~ /^(.+)---\s*FULL\s*---\s*$(.+)/m then
          headline_content = $1
          content = $2
          #item.raw_content = content
          attrs[:readmore] = item.identifier
        end
      end

      mtime = item.mtime
      headline = Nanoc::Item.new(headline_content, attrs, id, { :mtime => mtime, :binary => false })
      headline[:fullpost] = item.identifier
      @items << headline
    else
      raise "news file name does not start with a date (YYYY-MM-DD-...): #{item.id}"
    end
  end
end
