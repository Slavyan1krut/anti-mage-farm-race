from pathlib import Path
from struct import pack
from uuid import UUID
from xml.etree import ElementTree
from zlib import crc32


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "panorama"
OUTPUT = ROOT / "game/dota_addons/am_farm_race/panorama"
KV3_GENERIC = UUID("7412167c-06e9-4698-aff2-e63eb59037e7").bytes_le


def kv3(value):
    """Encode the string, array and object nodes used by Panorama's layout tree."""
    strings = {}
    words = [0]
    types = bytearray()

    def string_index(text):
        return strings.setdefault(text, len(strings))

    def write(node):
        if isinstance(node, str):
            types.append(6)
            words.append(string_index(node))
        elif isinstance(node, list):
            types.append(8)
            words.append(len(node))
            for child in node:
                write(child)
        else:
            types.append(9)
            words.append(len(node))
            for key, child in node.items():
                words.append(string_index(key))
                write(child)

    write(value)
    words[0] = len(strings)
    body = pack(f"<{len(words)}I", *words)
    body += bytes(-len(body) % 8)
    body += b"".join(text.encode("utf-8") + b"\0" for text in strings)
    body += types + pack("<I", 0xFFEEDD00)
    return pack("<I", 0x4B563301) + KV3_GENERIC + pack("<5I", 0, 0, len(words), 0, len(body)) + body


def resource(version, blocks):
    directory = bytearray()
    payload = bytearray()
    for index, (tag, contents) in enumerate(blocks):
        payload.extend(bytes(-len(payload) % 8))
        offset = 12 * (len(blocks) - index) + len(payload) - 4
        directory.extend(pack("<4sII", tag, offset, len(contents)))
        payload.extend(contents)
    return pack("<IHHII", 16 + len(directory) + len(payload), 12, version, 8, len(blocks)) + directory + payload


def layout_node(xml):
    def attribute_value(text):
        prefix = "file://{resources}/"
        if text.startswith(prefix):
            base, suffix = text[len(prefix):].rsplit(".", 1)
            return {"eType": "REFERENCE_COMPILED", "name": f"panorama/{base}.v{suffix}"}
        return {"eType": "PANEL_ATTRIBUTE_VALUE", "name": text}

    if xml.tag == "include":
        return {"eType": "INCLUDE", "child": attribute_value(xml.attrib["src"])}

    wrappers = {"root": "ROOT", "styles": "STYLES", "scripts": "SCRIPTS"}
    node = {"eType": wrappers.get(xml.tag, "PANEL")}
    if xml.tag not in wrappers:
        node["name"] = xml.tag
    children = [
        {"eType": "PANEL_ATTRIBUTE", "name": name, "child": attribute_value(value)}
        for name, value in xml.attrib.items()
    ]
    children.extend(layout_node(child) for child in xml)
    if len(children) == 1:
        node["child"] = children[0]
    elif children:
        node["vecChildren"] = children
    return node


def build_panorama():
    folders = {"xml": "layout", "css": "styles", "js": "scripts"}
    for path in sorted(SOURCE.iterdir()):
        extension = path.suffix[1:]
        if extension not in folders:
            continue
        source = path.read_bytes()
        data_header = pack("<IH", crc32(source), 0)
        if extension == "xml":
            tree = kv3({"m_AST": {"m_pRoot": layout_node(ElementTree.fromstring(source))}})
            compiled = resource(3, [(b"DATA", data_header), (b"LaCo", tree)])
        elif extension == "css":
            compiled = resource(3, [(b"DATA", data_header + source)])
        else:
            compiled = resource(4, [(b"DATA", source)])
        target = OUTPUT / folders[extension] / "custom_game" / f"{path.stem}.v{extension}_c"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(compiled)


if __name__ == "__main__":
    build_panorama()
