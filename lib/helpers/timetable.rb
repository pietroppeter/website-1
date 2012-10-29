# vim: set ts=2 sw=2 et ai ft=ruby fileencoding=utf-8:

module Fosdem
  def interval_minutes
    $_ti_interval_minutes ||= begin
                                require 'time'
                                td = $item_by_id.fetch("/schedule/conference/")[:timeslot_duration]
                                t = Time.parse(td)
                                raise "conference :timeslot_duration has seconds" unless t.sec == 0
                                raise "conference :timeslot_duration is less than 5 minutes" unless t.min >= 5
                                t.min + t.hour * 60
                              end
  end

  # Flatten a time (HH:MM[:SS]) to an index
  def ti(time)
    h,m = case time
          when String
            time.split(':').map(&:to_i)[0,2]
          when Time
            [time.hour, time.min]
          when Date
            [time.hour, time.min]
          when DateTime
            [time.hour, time.min]
          else
            raise "unsupported object of type #{time.class}: #{time.inspect}"
          end

    # maybe remove later, sanity check
    raise "time with granularity != 5 min: #{time}" if m % interval_minutes != 0

    (h * 60 + m) / interval_minutes
  end

  def timetable_from_items(items)
    h = {}
    items.select{|i| i.identifier =~ %r{^/schedule/day/.+}}.sort_by{|d| d[:conference_day]}.map do |day|
      h[day[:slug]] = timetable_from_items_for_day(items, day)
    end
    h
  end

  def timetable_from_items_for_day(items, day)
    rooms = items.select{|i| i.identifier =~ %r{^/schedule/room/.+}}
    .sort_by{|r| [r[:rank], r[:conference_room_id]]}

    events = items.select{|i| i.identifier =~ %r{^/schedule/event/.+}}
    .select{|e| e[:conference_day_id] == day[:conference_day_id]}
    .sort_by{|e| [e[:start_time], e[:event_id]]}

    timetable rooms, events
  end

  def timetable(rooms, events)
    require 'time'

    interval, step = begin
                       i = interval_minutes
                       raise "an interval under 5 minutes, really, are you serious?" if i < 5
                       # convert the interval to seconds for step as that's what we always need below
                       # to use the + operator on Time objects
                       [ i, i * 60 ]
                     end

    table_by_room = begin
                      table = {}
                      start_time = Time.parse(events.first[:start_time])
                      end_time   = Time.parse(events.last[:end_time])

                      rooms.each do |room|
                        column = {}
                        table[room[:slug]] = column

                        now = start_time
                        while now <= end_time
                          column[now.strftime("%H:%M")] = []
                          nb = now
                          now += step
                        end
                      end #rooms
                      table
                    end

    table_by_time = begin
                      table = {}
                      start_time = Time.parse(events.first[:start_time])
                      end_time   = Time.parse(events.last[:end_time])

                      now = start_time
                      while now <= end_time
                        row = {}
                        table[now.strftime("%H:%M")] = row
                        rooms.each do |room|
                          row[room[:slug]] = []
                        end #room

                        now += step
                      end
                      table
                    end

    table_by_index = begin
                       # fill table with empty arrays with index ranging from 0 to 24 hours flattened to the interval
                       i = 0
                       l = (24 * 60 + 0) / interval
                       a = []
                       while i < l
                         a[i] = []
                         i += 1
                       end
                       a
                     end

    # so, we have complete and empty tables now, let's fill them with
    # all events
    events.each do |event|
      # add event to index table from start_time to end_time
      begin
        (event[:start_time_index]..event[:end_time_index]).each do |i|
          table_by_index[i] << event[:slug]
        end
      end
      # post-process index table to use sets instead of arrays, as they
      # automatically get rid of duplicates, and they are a lot faster
      # for .include? lookups
      begin
        require 'set'
        i = 0
        l = (24 * 60 + 0) / interval
        while i < l
          table_by_index[i] = Set.new(table_by_index[i])
          i += 1
        end
      end

      slots = ti(event[:duration])
      now = Time.parse(event[:start_time])
      (0..slots-1).each do |slot|
        key = now.strftime("%H:%M")

        state = case slot
                when 0
                  :begin
                when slots-1
                  :end
                else
                  :inprogress
                end

        meta = {
          event_id: event[:event_id],
          title: event[:title],
          slug: event[:slug],
          track: event[:track],
          track_name: event[:track_name],
          state: state,
        }
        meta[:slots] = slots if slot == 0

        [
          table_by_room.fetch(event[:room]).fetch(key),
          table_by_time.fetch(key).fetch(event[:room]),
        ].each do |cells|
          cells << meta
        end

        now += step
      end
    end #events

    {
      by_time: table_by_time,
      by_room: table_by_room,
      by_index: table_by_index,
      interval: interval,
    }
  end

  def flatlist(compress=true)
    by_day = {}
    days.each do |d|
      interval = $timetable.fetch(d[:slug]).fetch(:interval)

      h = {}
      $timetable.fetch(d[:slug]).fetch(:by_room).each do |room, time_cells|
        h[room] = begin
                    clusters = []
                    cells = time_cells.values.map(&:first)
                    cells.each do |cell|
                      if cell.nil?
                        clusters << nil
                      elsif cell[:state] == :begin
                        clusters << cell
                      end
                    end

                    if compress
                      cc = []
                      i = 0
                      while i < clusters.size
                        cell = clusters[i]
                        if cell.nil?
                          cc << nil
                          i += 1
                        else
                          j = i + 1
                          xs = 0
                          xn = 0
                          xm = 0
                          while j < clusters.size and xn < (60 / interval)
                            fcell = clusters[j]
                            if fcell.nil?
                              xn += 1
                            elsif fcell[:track] == cell[:track]
                              xm += 1
                              xs += fcell[:slots]
                              xs += xn
                              xn = 0
                            else
                              break
                            end
                            j += 1
                          end
                          if xm > 0
                            cc << { track: cell[:track], slots: cell[:slots] + xs}
                            (0..xn-1).each do |n|
                              cc << nil
                            end
                            i = j
                          else
                            cc << cell
                            i += 1
                          end
                        end
                      end
                      cc
                    else
                      clusters
                    end
                  end
      end #room, time_cells
      by_day[d[:slug]] = h
    end

    by_day
  end

end
