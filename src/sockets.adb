-----------------------------------------------------------------------------
--                                                                         --
--                         ADASOCKETS COMPONENTS                           --
--                                                                         --
--                             S O C K E T S                               --
--                                                                         --
--                                B o d y                                  --
--                                                                         --
--          Copyright (C) 1998-2011 Samuel Tardieu <sam@rfc1149.net>       --
--                 Copyright (C) 1999-2003 Télécom ParisTech               --
--                                                                         --
--   AdaSockets is free software; you can  redistribute it and/or modify   --
--   it  under terms of the GNU  General  Public License as published by   --
--   the Free Software Foundation; either version 2, or (at your option)   --
--   any later version.   AdaSockets is distributed  in the hope that it   --
--   will be useful, but WITHOUT ANY  WARRANTY; without even the implied   --
--   warranty of MERCHANTABILITY   or FITNESS FOR  A PARTICULAR PURPOSE.   --
--   See the GNU General Public  License  for more details.  You  should   --
--   have received a copy of the  GNU General Public License distributed   --
--   with AdaSockets; see   file COPYING.  If  not,  write  to  the Free   --
--   Software  Foundation, 59   Temple Place -   Suite  330,  Boston, MA   --
--   02111-1307, USA.                                                      --
--                                                                         --
--   As a special exception, if  other  files instantiate generics  from   --
--   this unit, or  you link this  unit with other  files to produce  an   --
--   executable,  this  unit does  not  by  itself cause  the  resulting   --
--   executable to be  covered by the  GNU General Public License.  This   --
--   exception does  not  however invalidate any  other reasons  why the   --
--   executable file might be covered by the GNU Public License.           --
--                                                                         --
--   The main repository for this software is located at:                  --
--       http://www.rfc1149.net/devel/adasockets.html                      --
--                                                                         --
--   If you have any question, please use the issues tracker at:           --
--       https://github.com/samueltardieu/adasockets/issues                --
--                                                                         --
-----------------------------------------------------------------------------

with Ada.Characters.Latin_1;     use Ada.Characters.Latin_1;
with Ada.Unchecked_Deallocation;
with Sockets.Utils;              use Sockets.Utils;

package body Sockets is

   use Ada.Streams, Interfaces.C, GNAT.Sockets;

   CRLF : constant String := CR & LF;

   procedure Refill (Socket : Socket_FD'Class);
   --  Refill the socket when in buffered mode by receiving one packet
   --  and putting it in the buffer.

   function To_String (S : Stream_Element_Array) return String;

   function Empty_Buffer (Socket : Socket_FD'Class) return Boolean;
   --  Return True if buffered socket has an empty buffer

   -------------------
   -- Accept_Socket --
   -------------------

   procedure Accept_Socket (Socket     : Socket_FD;
                            New_Socket : out Socket_FD)
   is
      New_FD   : GNAT.Sockets.Socket_Type;
      New_Addr : Sock_Addr_Type;
   begin
      Accept_Socket (Socket.FD, New_FD, New_Addr);
      New_Socket :=
        (FD       => New_FD,
         Shutdown => (others => False),
         Buffer   => null);
   end Accept_Socket;

   ----------
   -- Bind --
   ----------

   procedure Bind
     (Socket : Socket_FD;
      Port   : Natural;
      Host   : String := "")
   is
      Address : Sock_Addr_Type;
   begin
      if Host = "" then
         Address.Addr := Any_Inet_Addr;
      elsif Is_IP_Address (Host) then
         Address.Addr := Inet_Addr (Host);
      else
         Address.Addr := Addresses (Get_Host_By_Name (Host), 1);
      end if;
      Address.Port := Port_Type (Port);
      Bind_Socket (Socket.FD, Address);
   end Bind;

   -------------
   -- Connect --
   -------------

   procedure Connect
     (Socket : Socket_FD;
      Host   : String;
      Port   : Positive)
   is
      Address : Sock_Addr_Type;
   begin
      Address.Port := Port_Type (Port);
      if Is_IP_Address (Host) then
         Address.Addr := Inet_Addr (Host);
         Connect_Socket (Socket.FD, Address);
      else
         declare
            E : constant Host_Entry_Type := Get_Host_By_Name (Host);
         begin
            for I in 1 .. Addresses_Length (E) loop
               begin
                  Address.Addr := Addresses (E, I);
                  Connect_Socket (Socket.FD, Address);
                  return;
               exception
                  when Socket_Error => null;
               end;
            end loop;
         end;

         --  We could not connect to any address corresponding to this
         --  host.

         Raise_With_Message
           ("Unable to connect to any address for host " & Host);
      end if;
   end Connect;

   ------------------
   -- Empty_Buffer --
   ------------------

   function Empty_Buffer (Socket : Socket_FD'Class) return Boolean is
   begin
      return Socket.Buffer.First > Socket.Buffer.Last;
   end Empty_Buffer;

   ---------
   -- Get --
   ---------

   function Get (Socket : Socket_FD'Class) return String
   is
   begin
      if Socket.Buffer /= null and then not Empty_Buffer (Socket) then
         declare
            S : constant String :=
              To_String (Socket.Buffer.Content
                         (Socket.Buffer.First .. Socket.Buffer.Last));
         begin
            Socket.Buffer.First := Socket.Buffer.Last + 1;
            return S;
         end;
      else
         return To_String (Receive (Socket));
      end if;
   end Get;

   --------------
   -- Get_Char --
   --------------

   function Get_Char (Socket : Socket_FD'Class) return Character is
      C : Stream_Element_Array (0 .. 0);
   begin
      if Socket.Buffer = null then
         --  Unbuffered mode

         Receive (Socket, C);
      else
         --  Buffered mode

         if Empty_Buffer (Socket) then
            Refill (Socket);
         end if;

         C (0) := Socket.Buffer.Content (Socket.Buffer.First);
         Socket.Buffer.First := Socket.Buffer.First + 1;

      end if;

      return Character'Val (C (0));
   end Get_Char;

   ------------
   -- Get FD --
   ------------

   function Get_FD (Socket : Socket_FD) return Interfaces.C.int is
   begin
      return Interfaces.C.int (To_C (Get_FD (Socket)));
   end Get_FD;

   ------------
   -- Get FD --
   ------------

   function Get_FD (Socket : Socket_FD) return GNAT.Sockets.Socket_Type is
   begin
      return Socket.FD;
   end Get_FD;

   --------------
   -- Get_Line --
   --------------

   procedure Get_Line
     (Socket : Socket_FD'Class;
      Str    : out String;
      Last   : out Natural)
   is
      Index  : Positive := Str'First;
      Char   : Character;
   begin
      loop
         Char := Get_Char (Socket);
         if Char = LF then
            Last := Index - 1;
            return;
         elsif Char /= CR then
            Str (Index) := Char;
            Index := Index + 1;
            if Index > Str'Last then
               Last := Str'Last;
               return;
            end if;
         end if;
      end loop;
   end Get_Line;

   --------------
   -- Get_Line --
   --------------

   function Get_Line
     (Socket : Socket_FD'Class;  Max_Length : Positive := 2048)
     return String
   is
      Result : String (1 .. Max_Length);
      Last   : Natural;
   begin
      Get_Line (Socket, Result, Last);
      return Result (1 .. Last);
   end Get_Line;

   ----------------
   -- Getsockopt --
   ----------------

   procedure Getsockopt
     (Socket  :  Socket_FD'Class;
      Level   :  Socket_Level := SOL_SOCKET;
      Optname :  Socket_Option;
      Optval  : out Integer)
   is
      Result : constant Option_Type :=
        Get_Socket_Option (Socket.FD, Level, Optname);
   begin
      case Optname is
         when SO_REUSEADDR | IP_MULTICAST_LOOP =>
            Optval := Boolean'Pos (Result.Enabled);
         when IP_MULTICAST_TTL =>
            Optval := Result.Time_To_Live;
         when SO_SNDBUF | SO_RCVBUF =>
            Optval := Result.Size;
         when others =>
            Raise_With_Message ("Unimplemented option for Getsockopt");
      end case;
   end Getsockopt;

   ------------
   -- Listen --
   ------------

   procedure Listen
     (Socket     : Socket_FD;
      Queue_Size : Positive := 5)
   is
   begin
      Listen_Socket (Socket.FD, Queue_Size);
   end Listen;

   --------------
   -- New_Line --
   --------------

   procedure New_Line (Socket : Socket_FD'Class;
                       Count  : Natural := 1)
   is
   begin
      Put (Socket, CRLF * Count);
   end New_Line;

   ---------
   -- Put --
   ---------

   procedure Put (Socket : Socket_FD'Class;
                  Str    : String)
   is
      Stream : Stream_Element_Array (Stream_Element_Offset (Str'First) ..
                                     Stream_Element_Offset (Str'Last));
   begin
      for I in Str'Range loop
         Stream (Stream_Element_Offset (I)) :=
           Stream_Element'Val (Character'Pos (Str (I)));
      end loop;
      Send (Socket, Stream);
   end Put;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (Socket : Socket_FD'Class; Str : String)
   is
   begin
      Put (Socket, Str & CRLF);
   end Put_Line;

   -------------
   -- Receive --
   -------------

   function Receive (Socket : Socket_FD; Max : Stream_Element_Count := 4096)
     return Stream_Element_Array
   is
      Buffer  : Stream_Element_Array (1 .. Max);
      Last    : Stream_Element_Offset;
   begin
      if Socket.Shutdown (Receive) then
         raise Connection_Closed;
      end if;
      Receive_Socket (Socket.FD, Buffer, Last);
      if Last = Buffer'First - 1 then
         raise Connection_Closed;
      end if;
      return Buffer (1 .. Last);
   end Receive;

   -------------
   -- Receive --
   -------------

   procedure Receive (Socket : Socket_FD'Class;
                      Data   : out Stream_Element_Array)
   is
      Last     : Stream_Element_Offset := Data'First - 1;
      Old_Last : Stream_Element_Offset;
   begin
      while Last < Data'Last loop
         Old_Last := Last;
         Receive_Socket (Socket.FD, Data (Last + 1 .. Data'Last), Last);
         if Last = Old_Last then
            raise Connection_Closed;
         end if;
      end loop;
   end Receive;

   ------------------
   -- Receive_Some --
   ------------------

   procedure Receive_Some (Socket : Socket_FD'Class;
                           Data   : out Stream_Element_Array;
                           Last   : out Stream_Element_Offset)
   is
   begin
      Receive_Socket (Socket.FD, Data, Last);
      if Last = Data'First - 1 then
         raise Connection_Closed;
      end if;
   end Receive_Some;

   ------------
   -- Refill --
   ------------

   procedure Refill
     (Socket : Socket_FD'Class)
   is
   begin
      pragma Assert (Socket.Buffer /= null);
      Receive_Some (Socket, Socket.Buffer.Content, Socket.Buffer.Last);
      Socket.Buffer.First := 0;
   end Refill;

   ----------
   -- Send --
   ----------

   procedure Send (Socket : Socket_FD;
                   Data   : Stream_Element_Array)
   is
      Last     : Stream_Element_Offset := Data'First - 1;
      Old_Last : Stream_Element_Offset;
   begin
      while Last /= Data'Last loop
         Old_Last := Last;
         Send_Socket (Socket.FD, Data (Last + 1 .. Data'Last), Last);
         if Last = Old_Last then
            raise Connection_Closed;
         end if;
      end loop;
   end Send;

   ----------
   -- Send --
   ----------

   procedure Send (Socket : Socket_FD;
                   Data   : Stream_Element_Array;
                   Target : Sock_Addr_Type)
   is
      Last     : Stream_Element_Offset := Data'First - 1;
      Old_Last : Stream_Element_Offset;
   begin
      while Last /= Data'Last loop
         Old_Last := Last;
         Send_Socket (Socket.FD, Data (Last + 1 .. Data'Last), Last, Target);
         if Last = Old_Last then
            raise Connection_Closed;
         end if;
      end loop;
   end Send;

   ----------------
   -- Set_Buffer --
   ----------------

   procedure Set_Buffer
     (Socket : in out Socket_FD'Class;
      Length : Positive := 1500)
   is
   begin
      Unset_Buffer (Socket);
      Socket.Buffer := new Buffer_Type (Stream_Element_Count (Length));
   end Set_Buffer;

   ----------------
   -- Setsockopt --
   ----------------

   procedure Setsockopt
     (Socket  : Socket_FD'Class;
      Level   : Socket_Level := SOL_SOCKET;
      Optname : Socket_Option;
      Optval  : Integer)
   is
   begin
      case Optname is
         when SO_REUSEADDR =>
            Set_Socket_Option
              (Socket.FD, Level, (Reuse_Address, Boolean'Val (Optval)));
         when IP_MULTICAST_TTL =>
            Set_Socket_Option
              (Socket.FD, Level, (Multicast_TTL, Optval));
         when IP_MULTICAST_LOOP =>
            Set_Socket_Option
              (Socket.FD, Level, (Multicast_Loop, Boolean'Val (Optval)));
         when SO_SNDBUF =>
            Set_Socket_Option
              (Socket.FD, Level, (Send_Buffer, Optval));
         when SO_RCVBUF =>
            Set_Socket_Option
              (Socket.FD, Level, (Receive_Buffer, Optval));
         when others =>
            Raise_With_Message ("Unimplemented option for Setsockopt");
      end case;
   end Setsockopt;

   --------------
   -- Shutdown --
   --------------

   procedure Shutdown (Socket : in out Socket_FD;
                       How    : Shutdown_Type := Both)
   is
   begin
      if How /= Both then
         Socket.Shutdown (How) := True;
      else
         Socket.Shutdown := (others => True);
      end if;
      Shutdown_Socket (Socket.FD, How);
      if Socket.Shutdown (Receive) and then Socket.Shutdown (Send) then
         Unset_Buffer (Socket);
         Close_Socket (Socket.FD);
      end if;
   end Shutdown;

   ------------
   -- Socket --
   ------------

   procedure Socket
     (Sock   : out Socket_FD;
      Domain : Socket_Domain := PF_INET;
      Typ    : Socket_Type   := SOCK_STREAM)
   is
   begin
      Create_Socket (Sock.FD, Domain, Typ);
      Sock.Shutdown := (others => False);
      Sock.Buffer   := null;
   end Socket;

   ---------------
   -- To_String --
   ---------------

   function To_String (S : Stream_Element_Array) return String is
      Result : String (1 .. S'Length);
   begin
      for I in Result'Range loop
         Result (I) :=
           Character'Val (Stream_Element'Pos
                          (S (Stream_Element_Offset (I) + S'First - 1)));
      end loop;
      return Result;
   end To_String;

   ------------------
   -- Unset_Buffer --
   ------------------

   procedure Unset_Buffer (Socket : in out Socket_FD'Class) is
      procedure Free is
         new Ada.Unchecked_Deallocation (Buffer_Type, Buffer_Access);
   begin
      Free (Socket.Buffer);
   end Unset_Buffer;

end Sockets;
