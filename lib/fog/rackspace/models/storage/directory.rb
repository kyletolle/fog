require 'fog/core/model'
require 'fog/rackspace/models/storage/files'
require 'fog/rackspace/models/storage/metadata'

module Fog
  module Storage
    class Rackspace

      class Directory < Fog::Model

        identity  :key, :aliases => 'name'

        attribute :bytes, :aliases => 'X-Container-Bytes-Used', :type => :integer
        attribute :count, :aliases => 'X-Container-Object-Count', :type => :integer
        attribute :cdn_cname

        def metadata=(hash)
          if hash.is_a? Fog::Storage::Rackspace::Metadata
            attributes[:metadata] = hash
          else
            attributes[:metadata] = Fog::Storage::Rackspace::Metadata.new(self, hash)
          end
          attributes[:metadata]
        end
        
        def metadata
          attributes[:metadata] ||= Fog::Storage::Rackspace::Metadata.new(self)
        end

        def destroy
          requires :key
          service.delete_container(key)
          service.cdn.post_container(key, 'X-CDN-Enabled' => 'False')
          true
        rescue Excon::Errors::NotFound
          false
        end

        def files
          @files ||= begin
            Fog::Storage::Rackspace::Files.new(
              :directory    => self,
              :service   => service
            )
          end
        end

        def public=(new_public)          
          @public = new_public
        end
        
        def public?
          @public ||= !public_url.nil?
        end

        def public_url
          requires :key
          @public_url ||= begin
            begin response = service.cdn.head_container(key)
              if response.headers['X-Cdn-Enabled'] == 'True'
                if service.rackspace_cdn_ssl == true
                  response.headers['X-Cdn-Ssl-Uri']
                else
                  cdn_cname || response.headers['X-Cdn-Uri']
                end
              end
            rescue Fog::Service::NotFound
              nil
            end
          end
        end

        def save
          requires :key
          service.put_container(key, metadata.to_headers)

          if service.cdn && public?
            # if public and CDN connection then update cdn to public
            uri_header = 'X-CDN-URI'
            if service.rackspace_cdn_ssl == true
              uri_header = 'X-CDN-SSL-URI'
            end
            @public_url = service.cdn.put_container(key, 'X-CDN-Enabled' => 'True').headers[uri_header]
          elsif service.cdn && !public?
            service.cdn.put_container(key, 'X-CDN-Enabled' => 'False')
            @public_url = nil
          elsif !service.cdn && public?
            # if public but no CDN connection then error
            raise(Fog::Storage::Rackspace::Error.new("Directory can not be set as :public without a CDN provided"))
          end
          true
        end

      end

    end
  end
end
