# Copyright (c) 2010 XAOP bvba
# 
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# 
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# 
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

module ActiveSP
  
  class Item < Base
    
    include InSite
    extend Caching
    include Util
    
    # Returns the list in which the item is located
    # @return [List]
    attr_reader :list
    
    # @private
    def initialize(list, id, folder = :unset, uid = nil, url = nil, attributes_before_type_cast = nil)
      @list, @id = list, id
      @folder = folder if folder != :unset # We have to allow for nil
      @uid = uid if uid
      @site = list.site
      @url = url if url
      @attributes_before_type_cast = attributes_before_type_cast if attributes_before_type_cast
    end
    
    # Returns the folder, if any, that this item is located in. NOT FULLY IMPLEMENTED YET
    # @return [Folder, nil]
    def folder
      raise ImplementationError, "finding the folder of an item is not supported yet"
    end
    cache :folder
    
    # Returns the parent of this item. NOT FULLY IMPLEMENTED YET
    # @return [Folder, List]
    def parent
      folder || @list
    end
    
    # @private
    def id
      uid
    end
    
    # @private
    def uid
      attributes["UniqueID"]
    end
    cache :uid
    
    # The URL of this item
    # @return [String]
    def url
      URL(@list.url).join(attributes["ServerUrl"]).to_s
    end
    cache :url
    
    # See {Base#key}
    # @return [String]
    def key
      encode_key("I", [@list.key, @id])
    end
    
    # Returns a list of the URLs of the attachments of this item. Note that for items in a document
    # library, this returns an empty list
    # @return [Array<String>]
    def attachments
      result = call("Lists", "get_attachment_collection", "listName" => @list.id, "listItemID" => @id)
      result.xpath("//sp:Attachment", NS).map { |att| att.text }
    end
    cache :attachments, :dup => :always
    
    # Returns a list of the content URLs for this item. For items in document libraries, this
    # returns the url, for other items this returns the attachments. These URLs can be used
    # to download all contents. See {Connection#fetch}
    # @return [Array<String>]
    def content_urls
      case @list.attributes["BaseType"]
      when "0", "5"
        attachments
      when "1"
        [url]
      else
        raise "not yet BaseType = #{@list.attributes["BaseType"].inspect}"
      end
    end
    cache :content_urls, :dup => :always
    
    # Returns the content type of this item
    # @return [ContentType]
    def content_type
      ContentType.new(@site, @list, attributes["ContentTypeId"])
    end
    cache :content_type
    
    # def versions
    #   call("Versions", "get_versions", "fileName" => attributes["ServerUrl"])
    # end
    
    # See {Base#save}
    # @return [void]
    def save
      update_attributes(untype_cast_attributes(@site, nil, internal_attribute_types, changed_attributes))
    end
    
    # @private
    def to_s
      "#<ActiveSP::Item url=#{url}>"
    end
    
    # @private
    alias inspect to_s
    
    def update_attributes(attributes)
      updates = Builder::XmlMarkup.new.Batch("OnError" => "Continue", "ListVersion" => 1) do |xml|
        xml.Method("ID" => 1, "Cmd" => "Update") do
          xml.Field(self.ID, "Name" => "ID")
          construct_xml_for_update_list_items(xml, @site, @list, @list.fields_by_name, attributes)
        end
      end
      result = call("Lists", "update_list_items", "listName" => @list.id, "updates" => updates)
      create_result = result.xpath("//sp:Result", NS).first
      error_code = create_result.xpath("./sp:ErrorCode", NS).first.text.to_i(0)
      if error_code == 0
        row = result.xpath("//z:row", NS).first
        @attributes_before_type_cast = clean_item_attributes(row.attributes)
        reload
      else
        raise "cannot create item, error code = #{error_code}"
      end
      self
    end
    
  private
    
    def data
      query_options = Builder::XmlMarkup.new.QueryOptions do |xml|
        xml.Folder
      end
      query = Builder::XmlMarkup.new.Query do |xml|
        xml.Where do |xml|
          xml.Eq do |xml|
            xml.FieldRef(:Name => "ID")
            xml.Value(@id, :Type => "Counter")
          end
        end
      end
      result = call("Lists", "get_list_items", "listName" => @list.id, "viewFields" => "<ViewFields></ViewFields>", "queryOptions" => query_options, "query" => query)
      result.xpath("//z:row", NS).first
    end
    cache :data
    
    def attributes_before_type_cast
      clean_item_attributes(data.attributes)
    end
    cache :attributes_before_type_cast
    
    def original_attributes
      type_cast_attributes(@site, @list, @list.fields_by_name, attributes_before_type_cast)
    end
    cache :original_attributes
    
    def current_attributes_before_type_cast
      untype_cast_attributes(@site, @list, @list.fields_by_name, current_attributes)
    end
    
    def internal_attribute_types
      list.fields_by_name
    end
    
  end
  
end
