
require 'rexml/document'

require_relative 'abstract_image_writer.rb'
require_relative 'phantom_xmldecl.rb'

module Phantom
  module SVG
    module Parser
      # SVG writer.
      class SVGWriter < AbstractImageWriter
        # Write svg file from object to path.
        # Return write size.
        def write(path, object)
          return 0 if path.nil? || path.empty? || object.nil?

          reset

          # Parse object.
          return 0 unless write_proc(object)

          # Add svg version.
          @root.elements['svg'].add_attribute('version', '1.1')

          # Write to file.
          File.open(path, 'w') { |file| @root.write(file, 2) }
        end

        private

        # Reset SVGWriter object.
        def reset
          @root = REXML::Document.new
          @root.context[:attribute_quote] = :quote
          @root << Phantom::SVG::Parser::PhantomXMLDecl.new('1.0', 'UTF-8')
          @root << REXML::Comment.new(' Generated by phantom_svg. ')
        end

        # Write procedure.
        def write_proc(object)
          if object.is_a?(Base)
            if object.frames.size == 1    then  write_svg(object.frames[0])
            elsif object.frames.size > 1  then  write_animation_svg(object)
            else                                return false
            end
          elsif object.is_a?(Frame)       then  write_svg(object)
          else                                  return false
          end

          true
        end

        # Write no animation svg.
        def write_svg(frame)
          write_image(frame, @root)
        end

        # Write animation svg.
        def write_animation_svg(base)
          svg = @root.add_element('svg', 'id' => 'phantom_svg')
          defs = svg.add_element('defs')

          # Header.
          write_size(base, svg)
          svg.add_namespace('http://www.w3.org/2000/svg')
          svg.add_namespace('xlink', 'http://www.w3.org/1999/xlink')

          # Images.
          write_images(base.frames, defs)

          # Animation.
          write_animation(base, defs)

          # Show control.
          write_show_control(base, svg)
        end

        # Write image size.
        def write_size(s, d)
          d.add_attribute('width', s.width.is_a?(String) ? s.width : "#{s.width.to_i}px")
          d.add_attribute('height', s.height.is_a?(String) ? s.height : "#{s.height.to_i}px")
        end

        # Write viewbox.
        def write_viewbox(s, d)
          d.add_attribute('viewBox', s.viewbox.to_s) if s.instance_variable_defined?(:@viewbox)
        end

        # Write namespaces from src to dest.
        def write_namespaces(src, dest)
          src.namespaces.each do |key, val|
            if key == 'xmlns' then  dest.add_namespace(val)
            else                    dest.add_namespace(key, val)
            end
          end
        end

        # Write surfaces to dest.
        def write_surfaces(surfaces, dest)
          surfaces.each { |surface| dest.add_element(Marshal.load(Marshal.dump(surface))) }
        end

        # Write image.
        def write_image(frame, parent_node, id = nil)
          svg = parent_node.add_element('svg')
          svg.add_attribute('id', id) unless id.nil?
          write_size(frame, svg) if parent_node == @root
          write_viewbox(frame, svg)
          svg.add_attribute('preserveAspectRatio', 'none')
          write_namespaces(frame, svg)
          write_surfaces(frame.surfaces, svg)
          convert_id_to_unique(svg, "#{id}_") unless id.nil?
        end

        # Write images.
        def write_images(frames, parent_node)
          REXML::Comment.new(' Images. ', parent_node)
          frames.each_with_index { |frame, i| write_image(frame, parent_node, "frame#{i}") }
        end

        # Write animation.
        def write_animation(base, parent_node)
          return if skip_frame_and_no_animation?(base)

          REXML::Comment.new(' Animation. ', parent_node)
          symbol = parent_node.add_element('symbol', 'id' => 'animation')

          begin_text = "0s;frame#{base.frames.length - 1}_anim.end"
          base.frames.each_with_index do |frame, i|
            next if i == 0 && base.skip_first

            write_animation_frame(frame, "frame#{i}", begin_text, symbol)

            begin_text = "frame#{i}_anim.end"
          end
        end

        def write_animation_frame(frame, id, begin_text, parent)
          use = parent.add_element('use', 'xlink:href' => "##{id}",
                                          'visibility' => 'hidden')

          use.add_element('set',  'id' => "#{id}_anim",
                                  'attributeName' => 'visibility',
                                  'to' => 'visible',
                                  'begin' => begin_text,
                                  'dur' => "#{frame.duration}s")
        end

        # Write show control.
        def write_show_control(base, parent_node)
          REXML::Comment.new(' Main control. ', parent_node)

          if skip_frame_and_no_animation?(base)
            write_show_control_main_2(parent_node)
          else
            write_show_control_header(base, parent_node)
            write_show_control_main(base, parent_node)
          end
        end

        # Write show control header.
        def write_show_control_header(base, parent_node)
          repeat_count = base.loops.to_i == 0 ? 'indefinite' : base.loops.to_i.to_s

          parent_node.add_element('animate',  'id' => 'controller',
                                              'begin' => '0s',
                                              'dur' => "#{base.total_duration}s",
                                              'repeatCount' => repeat_count)
        end

        # Write show control main.
        def write_show_control_main(base, parent_node)
          use = parent_node.add_element('use', 'xlink:href' => '#frame0')

          use.add_element('set',  'attributeName' => 'xlink:href',
                                  'to' => '#animation',
                                  'begin' => 'controller.begin')

          use.add_element('set',  'attributeName' => 'xlink:href',
                                  'to' => "#frame#{base.frames.length - 1}",
                                  'begin' => 'controller.end')
        end

        # Write show control main.
        def write_show_control_main_2(parent_node)
          use = parent_node.add_element('use', 'xlink:href' => '#frame0')

          use.add_element('set',  'attributeName' => 'xlink:href',
                                  'to' => '#frame1',
                                  'begin' => '0s')
        end

        # Convert id.
        def convert_id_to_unique(root_node, prefix)
          id_array = []
          overwrite_id(root_node, prefix, id_array)
          overwrite_relative_id(root_node, prefix, id_array)
        end

        # Overwrite id in surfaces.
        def overwrite_id(parent_node, prefix, out_id_array)
          parent_node.elements.each do |child|
            old_id = child.attributes['id']
            unless old_id.nil?
              out_id_array << old_id
              child.add_attribute('id', "#{prefix}#{old_id}")
            end
            overwrite_id(child, prefix, out_id_array)
          end
        end

        # Overwrite relative id in surfaces.
        def overwrite_relative_id(parent_node, prefix, id_array)
          parent_node.elements.each do |child|
            child.attributes.each do |_, val|
              id_array.each do |id|
                val.gsub!("##{id}", "##{prefix}#{id}")
              end
            end
            overwrite_relative_id(child, prefix, id_array)
          end
        end

        # If base has skip frame and no animation, return true.
        def skip_frame_and_no_animation?(base)
          base.skip_first == true && base.frames.size == 2
        end
      end # class SVGWriter
    end # module Parser
  end # module SVG
end # module Phantom
