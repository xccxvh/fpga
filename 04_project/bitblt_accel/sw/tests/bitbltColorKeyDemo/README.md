# BitBlt Color Key Demo

验证`OPERATION=2`的RGB565 Color Key Copy。透明判断比较完整16位像素，
忽略X字节；匹配键值的源像素保留原目标像素，其余像素正常复制。

测试使用20×5像素、不同源/目标stride，检查全部有效像素、目标行尾padding和
目标区域前后哨兵，并验证完成中断。
