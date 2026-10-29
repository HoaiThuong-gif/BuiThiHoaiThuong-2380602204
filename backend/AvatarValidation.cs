using System.Buffers.Binary;
namespace NhomBar;

public static class AvatarValidation
{
    public static byte[] Read(string encoded)
    {
        Check.That(encoded.Length <= 350000, "Ảnh quá lớn. Hãy chọn ảnh nhỏ hơn.");
        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(encoded);
        }
        catch (FormatException) { throw new AppError(400, "Ảnh chưa hợp lệ. Hãy chọn ảnh khác."); }
        Check.That(bytes.Length is > 24 and <= 262144, "Ảnh quá lớn hoặc chưa hợp lệ.");
        int width = 0, height = 0;
        if (bytes.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
        {
            width = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(16, 4));
            height = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(20, 4));
        }
        else if (bytes[0] == 255 && bytes[1] == 216)
        {
            for (int offset = 2; offset + 3 < bytes.Length;)
            {
                if (bytes[offset++] != 255)
                    break;
                var marker = bytes[offset++];
                if (marker == 255)
                {
                    offset--;
                    continue;
                }
                if (marker is 216 or 217)
                    continue;
                int length = BinaryPrimitives.ReadUInt16BigEndian(bytes.AsSpan(offset, 2));
                if (length < 2 || offset + length > bytes.Length)
                    break;
                if (marker is 192 or 193 or 194 && length >= 8)
                {
                    height = BinaryPrimitives.ReadUInt16BigEndian(bytes.AsSpan(offset + 3, 2));
                    width = BinaryPrimitives.ReadUInt16BigEndian(bytes.AsSpan(offset + 5, 2));
                    break;
                }
                offset += length;
            }
        }
        Check.That(width is > 0 and <= 1024 && height is > 0 and <= 1024, "Hãy chọn ảnh JPG hoặc PNG kích thước tối đa 1024 × 1024.");
        return bytes;
    }
}
