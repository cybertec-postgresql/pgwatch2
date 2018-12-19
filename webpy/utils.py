
def makePrettySize(size):   # copied from https://github.com/zalando/PGObserver
    """ mimics pg_size_pretty() """
    sign = '-' if size < 0 else ''
    size = abs(size)
    if size <= 1024:
        return sign + str(size) + ' B'
    if size < 10 * 1024**2:
        return sign + str(int(round(size / float(1024)))) + ' kB'
    if size < 10 * 1024**3:
        return sign + str(int(round(size / float(1024**2)))) + ' MB'
    if size < 10 * 1024**4:
        return sign + str(int(round(size / float(1024**3)))) + ' GB'
    return sign + str(int(round(size / float(1024**4)))) + ' TB'


def makePrettyCounter(count):
    sign = '-' if count < 0 else ''
    count = abs(count)
    if count <= 1000:
        return sign + str(count)
    if count < 1000**2:
        return sign + str(round(count / float(1000), 1)) + ' K'
    if count < 1000**3:
        return sign + str(round(count / float(1000**2), 1)) + ' M'
    return sign + str(round(count / float(1000**3), 1)) + ' B'

def fileContentsToString(filePath):
    with open(filePath) as f:
        return f.read()


if __name__ == '__main__':
    print(makePrettySize(2.2 * 1e9))
    print(makePrettyCounter(2.2 * 1e9))
    print(fileContentsToString(__file__))

